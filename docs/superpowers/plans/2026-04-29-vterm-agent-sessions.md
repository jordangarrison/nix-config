# VTerm Agent Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the primary Doom Emacs agent keybindings with workspace-aware CLI agents running inside `vterm`, while keeping `agent-shell` installed and available.

**Architecture:** Add a focused `jag/agent-vterm-*` layer in `users/jordangarrison/tools/doom.d/config.org`. The layer owns a small agent definition registry, workspace-local vterm session lifecycle, session selectors, context-rich region formatting, and paste-without-submit behavior. Existing `agent-shell` package/config remains, but conflicting primary bindings move to vterm agents.

**Tech Stack:** Doom Emacs, Emacs Lisp, `vterm`, Doom workspaces/persp-mode, Projectile/Doom project helpers, `emacsclient --eval` verification.

---

## Scope Check

The spec is one cohesive subsystem: vterm-backed Emacs agent sessions. It touches only Doom configuration and documentation. It does not require Nix package changes, Home Manager module changes, or ACP adapter changes.

## File Structure

- Modify: `users/jordangarrison/tools/doom.d/config.org`
  - Add a new `** VTerm Agent Sessions` section before `*** Agent Shell Configuration`.
  - Replace conflicting `agent-shell` keybindings with vterm-agent keybindings.
  - Remove the old generic `** VTerm Integration` region-to-`*vterm*` section.
- Generated/checked: `users/jordangarrison/tools/doom.d/config.el`
  - This file is generated from `config.org`; do not hand-edit it. Verify the running Emacs config after tangling/reloading as needed.
- No package changes: `users/jordangarrison/tools/doom.d/packages.el` already enables Doom's `vterm` module through `init.el`; no new package declaration is needed.

## Implementation Notes

- Follow `users/jordangarrison/tools/doom.d/AGENTS.md`: prefer `emacsclient --eval` for integration checks against the running Emacs server.
- Do not use `emacs --batch -Q` as the primary integration signal.
- Do not remove `agent-shell`, `acp`, or `shell-maker` from `packages.el`.
- Do not run `doom sync`; no package declarations change in this plan.

---

### Task 1: Add workspace-aware vterm agent session layer

**Files:**
- Modify: `users/jordangarrison/tools/doom.d/config.org`

- [ ] **Step 1: Run the failing integration probe**

Run this before adding the new code:

```bash
emacsclient --eval '(list (fboundp '\''jag/agent-vterm-start-or-switch) (fboundp '\''jag/agent-vterm-send-region))'
```

Expected output before implementation:

```text
(nil nil)
```

If either function already exists, stop and inspect the existing implementation before continuing.

- [ ] **Step 2: Insert the new `VTerm Agent Sessions` section**

In `users/jordangarrison/tools/doom.d/config.org`, insert this section immediately before the existing heading:

```org
*** Agent Shell Configuration
```

Insert exactly this new section:

```org
** VTerm Agent Sessions
Workspace-aware CLI coding agents running inside `vterm`. These sessions are the primary interactive agent workflow; `agent-shell` remains installed and configured separately.

#+begin_src emacs-lisp
(require 'cl-lib)
(require 'subr-x)

(defvar jag/agent-vterm-definitions
  '(("claude"
     :label "Claude"
     :command ("claude" "--dangerously-skip-permissions")
     :scope workspace)
    ("codex"
     :label "Codex"
     :command ("codex" "--yolo")
     :scope workspace)
    ("pi"
     :label "Pi"
     :command ("pi")
     :scope workspace))
  "Built-in vterm agent definitions.

Each entry is shaped like a future profile registry entry so this can grow
from tool-named agents into role-named agents such as codex-reviewer or
pi-implementer without replacing the session layer.")

(defvar-local jag/agent-vterm-agent-name nil
  "Agent definition name associated with the current vterm buffer.")

(defvar-local jag/agent-vterm-command nil
  "Command list used to start the current vterm agent session.")

(defvar-local jag/agent-vterm-launch-workspace-name nil
  "Doom workspace name active when this vterm agent was launched.")

(defvar-local jag/agent-vterm-launch-project-root nil
  "Normalized project root active when this vterm agent was launched.")

(defvar-local jag/agent-vterm-launch-default-directory nil
  "Normalized `default-directory' active when this vterm agent was launched.")

(defvar-local jag/agent-vterm-scope 'workspace
  "Scope for the current vterm agent session.")

(defun jag/agent-vterm--normalize-dir (path)
  "Return PATH normalized as a directory string suitable for equality checks."
  (when (and path (stringp path) (not (string-empty-p path)))
    (file-name-as-directory (file-truename path))))

(defun jag/agent-vterm--current-workspace-name ()
  "Return current Doom workspace name, or nil when workspaces are unavailable."
  (when (and (fboundp '+workspace-current-name)
             (bound-and-true-p persp-mode))
    (ignore-errors (+workspace-current-name))))

(defun jag/agent-vterm--current-project-root ()
  "Return normalized project root for the current launch context."
  (jag/agent-vterm--normalize-dir
   (or (and (fboundp 'doom-project-root) (doom-project-root))
       default-directory)))

(defun jag/agent-vterm--agent-definition (agent-name)
  "Return the vterm agent definition for AGENT-NAME."
  (assoc agent-name jag/agent-vterm-definitions))

(defun jag/agent-vterm--agent-command (agent-name)
  "Return command list for AGENT-NAME."
  (let ((definition (jag/agent-vterm--agent-definition agent-name)))
    (unless definition
      (user-error "Unknown vterm agent: %s" agent-name))
    (plist-get (cdr definition) :command)))

(defun jag/agent-vterm--agent-scope (agent-name)
  "Return configured scope for AGENT-NAME."
  (or (plist-get (cdr (jag/agent-vterm--agent-definition agent-name)) :scope)
      'workspace))

(defun jag/agent-vterm--agent-label (agent-name)
  "Return display label for AGENT-NAME."
  (or (plist-get (cdr (jag/agent-vterm--agent-definition agent-name)) :label)
      agent-name))

(defun jag/agent-vterm--available-agent-names ()
  "Return configured vterm agent names."
  (mapcar #'car jag/agent-vterm-definitions))

(defun jag/agent-vterm--shell-command (command)
  "Return shell-safe command string for COMMAND list."
  (combine-and-quote-strings command))

(defun jag/agent-vterm--ensure-executable (command)
  "Raise a clear error unless COMMAND's executable exists."
  (let ((executable (car command)))
    (unless (and executable (executable-find executable))
      (user-error "Missing executable for vterm agent: %s" executable))))

(defun jag/agent-vterm--safe-name-part (value fallback)
  "Return VALUE cleaned for use in an agent buffer name, or FALLBACK."
  (let ((raw (if (and value (stringp value) (not (string-empty-p value)))
                 value
               fallback)))
    (replace-regexp-in-string "[^[:alnum:]_.-]+" "-" raw)))

(defun jag/agent-vterm--session-buffer-name (agent-name workspace project-root)
  "Return stable vterm session buffer name for AGENT-NAME."
  (let* ((project-name (and project-root
                            (file-name-nondirectory
                             (directory-file-name project-root))))
         (context (jag/agent-vterm--safe-name-part
                   workspace
                   (or project-name "global"))))
    (format "*agent:%s:%s*" context agent-name)))

(defun jag/agent-vterm--register-buffer-in-workspace (buffer workspace-name)
  "Add BUFFER to the Doom workspace named WORKSPACE-NAME, if possible."
  (when (and buffer
             (buffer-live-p buffer)
             workspace-name
             (bound-and-true-p persp-mode)
             (fboundp 'persp-get-by-name)
             (fboundp 'persp-add-buffer))
    (condition-case _err
        (when-let ((persp (persp-get-by-name workspace-name)))
          (persp-add-buffer buffer persp nil nil))
      (error nil))))

(defun jag/agent-vterm--live-buffers ()
  "Return live vterm buffers managed by `jag/agent-vterm'."
  (seq-filter (lambda (buffer)
                (and (buffer-live-p buffer)
                     (with-current-buffer buffer
                       (and jag/agent-vterm-agent-name
                            (derived-mode-p 'vterm-mode)))))
              (buffer-list)))

(defun jag/agent-vterm--buffer-project-root (buffer)
  "Return normalized launch project root for BUFFER, with fallbacks."
  (with-current-buffer buffer
    (or jag/agent-vterm-launch-project-root
        (jag/agent-vterm--normalize-dir default-directory))))

(defun jag/agent-vterm--matching-session (agent-name workspace)
  "Return live workspace-local session buffer for AGENT-NAME and WORKSPACE."
  (seq-find (lambda (buffer)
              (with-current-buffer buffer
                (and (string= agent-name jag/agent-vterm-agent-name)
                     (equal 'workspace jag/agent-vterm-scope)
                     (equal workspace jag/agent-vterm-launch-workspace-name))))
            (jag/agent-vterm--live-buffers)))

(defun jag/agent-vterm--display-buffer (buffer)
  "Display BUFFER as the active window."
  (unless (buffer-live-p buffer)
    (user-error "Vterm agent buffer is no longer live"))
  (pop-to-buffer buffer))

(defun jag/agent-vterm-start-or-switch (agent-name)
  "Start or switch to workspace-local vterm agent AGENT-NAME."
  (interactive
   (list (completing-read "Agent: "
                          (jag/agent-vterm--available-agent-names)
                          nil t)))
  (let* ((command (jag/agent-vterm--agent-command agent-name))
         (scope (jag/agent-vterm--agent-scope agent-name))
         (workspace (jag/agent-vterm--current-workspace-name))
         (project-root (jag/agent-vterm--current-project-root))
         (default-dir (jag/agent-vterm--normalize-dir default-directory))
         (existing (jag/agent-vterm--matching-session agent-name workspace)))
    (jag/agent-vterm--ensure-executable command)
    (if existing
        (jag/agent-vterm--display-buffer existing)
      (require 'vterm)
      (let* ((buffer-name (jag/agent-vterm--session-buffer-name
                           agent-name workspace project-root))
             (default-directory (or project-root default-dir default-directory))
             (buffer (vterm buffer-name)))
        (with-current-buffer buffer
          (setq-local jag/agent-vterm-agent-name agent-name)
          (setq-local jag/agent-vterm-command command)
          (setq-local jag/agent-vterm-launch-workspace-name workspace)
          (setq-local jag/agent-vterm-launch-project-root project-root)
          (setq-local jag/agent-vterm-launch-default-directory default-dir)
          (setq-local jag/agent-vterm-scope scope)
          (vterm-send-string (jag/agent-vterm--shell-command command))
          (vterm-send-return))
        (jag/agent-vterm--register-buffer-in-workspace buffer workspace)
        (jag/agent-vterm--display-buffer buffer)))))

(defun jag/agent-vterm-start-or-switch-claude ()
  "Start or switch to the current workspace's Claude vterm agent."
  (interactive)
  (jag/agent-vterm-start-or-switch "claude"))

(defun jag/agent-vterm-start-or-switch-codex ()
  "Start or switch to the current workspace's Codex vterm agent."
  (interactive)
  (jag/agent-vterm-start-or-switch "codex"))

(defun jag/agent-vterm-start-or-switch-pi ()
  "Start or switch to the current workspace's Pi vterm agent."
  (interactive)
  (jag/agent-vterm-start-or-switch "pi"))

(defun jag/agent-vterm--candidate-label (buffer)
  "Return a display label for BUFFER suitable for completing-read."
  (with-current-buffer buffer
    (let* ((bname (buffer-name buffer))
           (ws (or jag/agent-vterm-launch-workspace-name "-"))
           (root (jag/agent-vterm--buffer-project-root buffer))
           (proj (and root (file-name-nondirectory (directory-file-name root))))
           (agent (or jag/agent-vterm-agent-name "-")))
      (format "%s  [%s | ws:%s]  {%s}"
              bname
              (or proj "-")
              ws
              agent))))

(defun jag/agent-vterm--uniquify-candidates (alist)
  "Disambiguate duplicate keys in ALIST by appending suffixes."
  (let ((counts (make-hash-table :test #'equal))
        (seen (make-hash-table :test #'equal))
        out)
    (dolist (cell alist)
      (puthash (car cell) (1+ (gethash (car cell) counts 0)) counts))
    (dolist (cell alist)
      (let* ((label (car cell))
             (total (gethash label counts 0)))
        (if (= total 1)
            (push cell out)
          (let ((idx (1+ (gethash label seen 0))))
            (puthash label idx seen)
            (push (cons (format "%s [%d]" label idx) (cdr cell)) out)))))
    (nreverse out)))

(defun jag/agent-vterm--prompt-for-buffer (prompt buffers empty-message)
  "Prompt for one of BUFFERS using PROMPT and return it."
  (unless buffers
    (user-error "%s" empty-message))
  (let* ((alist (mapcar (lambda (buffer)
                          (cons (jag/agent-vterm--candidate-label buffer) buffer))
                        buffers))
         (labeled (jag/agent-vterm--uniquify-candidates alist))
         (choice (condition-case nil
                     (completing-read prompt (mapcar #'car labeled) nil t)
                   (quit nil))))
    (and choice (cdr (assoc choice labeled)))))

(defun jag/agent-vterm--prompt-and-switch (prompt buffers empty-message)
  "Prompt for one of BUFFERS using PROMPT, then switch to it."
  (when-let ((buffer (jag/agent-vterm--prompt-for-buffer prompt buffers empty-message)))
    (jag/agent-vterm--display-buffer buffer)))

(defun jag/agent-vterm-switch-session ()
  "Switch to a live vterm agent session chosen via `completing-read'."
  (interactive)
  (jag/agent-vterm--prompt-and-switch
   "Active vterm agent session: "
   (jag/agent-vterm--live-buffers)
   "No active vterm agent sessions"))

(defun jag/agent-vterm-switch-project-session ()
  "Switch to a live vterm agent session in the current project."
  (interactive)
  (let* ((current-root (jag/agent-vterm--current-project-root))
         (matches (and current-root
                       (seq-filter (lambda (buffer)
                                     (let ((root (jag/agent-vterm--buffer-project-root buffer)))
                                       (and root (string= root current-root))))
                                   (jag/agent-vterm--live-buffers))))
         (label (and current-root
                     (file-name-nondirectory (directory-file-name current-root)))))
    (jag/agent-vterm--prompt-and-switch
     (format "Project vterm agent [%s]: " (or label "?"))
     matches
     (format "No active vterm agent sessions in project %s" (or label "(unknown)")))))

(defun jag/agent-vterm-switch-workspace-session ()
  "Switch to a live vterm agent session in the current Doom workspace."
  (interactive)
  (let* ((workspace (jag/agent-vterm--current-workspace-name))
         (matches (seq-filter
                   (lambda (buffer)
                     (with-current-buffer buffer
                       (or (and workspace
                                jag/agent-vterm-launch-workspace-name
                                (string= workspace jag/agent-vterm-launch-workspace-name))
                           (and workspace
                                (fboundp 'persp-get-by-name)
                                (fboundp 'persp-contain-buffer-p)
                                (when-let ((persp (ignore-errors (persp-get-by-name workspace))))
                                  (ignore-errors (persp-contain-buffer-p buffer persp)))))))
                   (jag/agent-vterm--live-buffers))))
    (jag/agent-vterm--prompt-and-switch
     (format "Workspace vterm agent [%s]: " (or workspace "?"))
     matches
     (format "No active vterm agent sessions in workspace %s" (or workspace "(unknown)")))))

(defun jag/agent-vterm--workspace-buffers ()
  "Return live vterm agent buffers associated with the current Doom workspace."
  (let ((workspace (jag/agent-vterm--current-workspace-name)))
    (seq-filter (lambda (buffer)
                  (with-current-buffer buffer
                    (and workspace
                         jag/agent-vterm-launch-workspace-name
                         (string= workspace jag/agent-vterm-launch-workspace-name))))
                (jag/agent-vterm--live-buffers))))

(defun jag/agent-vterm--select-target-for-send ()
  "Return target vterm agent buffer for sending selected context."
  (let ((workspace-buffers (jag/agent-vterm--workspace-buffers)))
    (cond
     ((= 1 (length workspace-buffers))
      (car workspace-buffers))
     ((> (length workspace-buffers) 1)
      (jag/agent-vterm--prompt-for-buffer
       "Send region to vterm agent: "
       workspace-buffers
       "No active vterm agent sessions in this workspace"))
     (t
      (let ((agent-name (completing-read "Start agent for region: "
                                         (jag/agent-vterm--available-agent-names)
                                         nil t)))
        (jag/agent-vterm-start-or-switch agent-name)
        (jag/agent-vterm--matching-session
         agent-name
         (jag/agent-vterm--current-workspace-name)))))))

(defun jag/agent-vterm--region-line-range (start end)
  "Return cons of 1-based line numbers covered by START and END."
  (let ((first-line (line-number-at-pos start t))
        (last-line (save-excursion
                     (goto-char end)
                     (when (and (> end start) (bolp))
                       (backward-char 1))
                     (line-number-at-pos (point) t))))
    (cons first-line last-line)))

(defun jag/agent-vterm--file-display-path (file project-root)
  "Return FILE relative to PROJECT-ROOT when possible, else absolute FILE."
  (let ((absolute-file (file-truename file))
        (root (jag/agent-vterm--normalize-dir project-root)))
    (if (and root (file-in-directory-p absolute-file root))
        (file-relative-name absolute-file root)
      absolute-file)))

(defun jag/agent-vterm-format-region-context (start end target-buffer)
  "Return context-rich prompt for region START END targeting TARGET-BUFFER."
  (unless (buffer-file-name)
    (user-error "Current buffer is not visiting a file"))
  (let* ((source-file (buffer-file-name))
         (line-range (jag/agent-vterm--region-line-range start end))
         (content (buffer-substring-no-properties start end))
         (project-root (and target-buffer
                            (buffer-live-p target-buffer)
                            (jag/agent-vterm--buffer-project-root target-buffer)))
         (file-label (jag/agent-vterm--file-display-path source-file project-root))
         (root-line (and project-root
                         (format "Project root: %s\n" (directory-file-name project-root)))))
    (format "%sFile: %s\nLines: %s-%s\n\nContent:\n%s"
            (or root-line "")
            file-label
            (car line-range)
            (cdr line-range)
            content)))

(defun jag/agent-vterm-send-region (start end)
  "Paste selected region with file context into a vterm agent without submitting."
  (interactive "r")
  (unless (use-region-p)
    (user-error "Select a region to send to a vterm agent"))
  (let* ((source-buffer (current-buffer))
         (target-buffer (jag/agent-vterm--select-target-for-send)))
    (unless (and target-buffer (buffer-live-p target-buffer))
      (user-error "No vterm agent session selected"))
    (let ((payload (with-current-buffer source-buffer
                     (jag/agent-vterm-format-region-context start end target-buffer))))
      (jag/agent-vterm--display-buffer target-buffer)
      (with-current-buffer target-buffer
        (unless (derived-mode-p 'vterm-mode)
          (user-error "Target buffer is not a vterm session: %s" (buffer-name target-buffer)))
        (unless (get-buffer-process target-buffer)
          (user-error "Target vterm process is not running: %s" (buffer-name target-buffer)))
        (vterm-send-string payload t)))))

(defun jag/agent-vterm-send-region-and-submit (start end)
  "Paste selected region with context into a vterm agent and submit it."
  (interactive "r")
  (jag/agent-vterm-send-region start end)
  (when (derived-mode-p 'vterm-mode)
    (vterm-send-return)))
#+end_src
```

- [ ] **Step 3: Evaluate/tangle the changed config enough for live checks**

Use the normal Doom/Org workflow available in the running Emacs server. One acceptable path is:

```bash
emacsclient --eval '(progn (find-file "~/dev/jordangarrison/nix-config/users/jordangarrison/tools/doom.d/config.org") (org-babel-tangle) (load-file "~/dev/jordangarrison/nix-config/users/jordangarrison/tools/doom.d/config.el") t)'
```

Expected output:

```text
t
```

If the path differs on the current machine, use the absolute repo path:

```text
/home/jordangarrison/dev/jordangarrison/nix-config/users/jordangarrison/tools/doom.d/config.org
```

- [ ] **Step 4: Verify the new functions and definitions exist**

Run:

```bash
emacsclient --eval '(list (fboundp '\''jag/agent-vterm-start-or-switch) (fboundp '\''jag/agent-vterm-send-region) jag/agent-vterm-definitions)'
```

Expected output includes `t`, `t`, and the three built-in agent definitions:

```text
(t t (("claude" :label "Claude" :command ("claude" "--dangerously-skip-permissions") :scope workspace) ("codex" :label "Codex" :command ("codex" "--yolo") :scope workspace) ("pi" :label "Pi" :command ("pi") :scope workspace)))
```

- [ ] **Step 5: Commit the session layer**

```bash
git add users/jordangarrison/tools/doom.d/config.org users/jordangarrison/tools/doom.d/config.el
git commit -m "feat(doom): add vterm agent session layer"
```

Expected result: a commit containing the new `VTerm Agent Sessions` section and the tangled `config.el` change.

---

### Task 2: Replace primary agent and session keybindings

**Files:**
- Modify: `users/jordangarrison/tools/doom.d/config.org`

- [ ] **Step 1: Capture the current conflicting keybinding state**

Run after Task 1 is loaded but before editing keybindings:

```bash
emacsclient --eval '(list (key-binding (kbd "SPC j a c")) (key-binding (kbd "SPC j a p")) (key-binding (kbd "SPC j a x")) (key-binding (kbd "SPC j a t")))'
```

Expected current output before this task still references old commands for at least the agent keys or old region sender:

```text
(agent-shell-anthropic-start-claude-code jag/agent-shell-pi-disabled agent-shell-openai-start-codex jag/send-region-to-vterm)
```

If Doom reports a different representation, continue only if the commands still point to the old `agent-shell` or generic vterm sender behavior.

- [ ] **Step 2: Replace the `map!` form in `Agent Shell Configuration`**

In `users/jordangarrison/tools/doom.d/config.org`, replace the existing `map! :leader` form in the `*** Agent Shell Configuration` source block with this form:

```emacs-lisp
(map! :leader
      :desc "Agent shell" "j a a" #'agent-shell
      :desc "Agent shell compose prompt" "j a e" #'jag/agent-shell-prompt-compose-bottom
      :desc "Agent shell queue request" "j a q" #'agent-shell-queue-request
      :desc "Vterm agent Claude" "j a c" #'jag/agent-vterm-start-or-switch-claude
      :desc "Vterm agent Pi" "j a p" #'jag/agent-vterm-start-or-switch-pi
      :desc "Vterm agent Codex" "j a x" #'jag/agent-vterm-start-or-switch-codex
      :desc "Vterm agent switch session" "j a s" #'jag/agent-vterm-switch-session
      :desc "Vterm agent switch project session" "j a S" #'jag/agent-vterm-switch-project-session
      :desc "Vterm agent switch workspace session" "j a w" #'jag/agent-vterm-switch-workspace-session
      :desc "Send region to vterm agent" "j a t" #'jag/agent-vterm-send-region)
```

This keeps `agent-shell` available at `SPC j a a`, compose at `SPC j a e`, and queue at `SPC j a q`, but moves the primary launch, switch, and region-send workflow to vterm agents.

- [ ] **Step 3: Remove the old generic `VTerm Integration` section**

In `users/jordangarrison/tools/doom.d/config.org`, delete the old section whose heading is:

```org
** VTerm Integration
```

Delete the entire old section body through its closing source block, including these obsolete definitions and binding:

```emacs-lisp
(defun jag/send-to-vterm (text)
  "Send TEXT to vterm buffer."
  (interactive "MText to send: ")
  (let ((vterm-buf (get-buffer "*vterm*")))
    (if vterm-buf
        (with-current-buffer vterm-buf
          (vterm-send-string text)))
    (message "No *vterm* buffer found")))

(defun jag/send-region-to-vterm (start end)
  "Send the region between START and END to the current vterm buffer."
  (interactive "r")
  (let ((text (buffer-substring-no-properties start end)))
    (jag/send-to-vterm text)))

(map! :leader :desc "Send code to vterm" "j a t" #'jag/send-region-to-vterm)
```

- [ ] **Step 4: Tangle and reload the changed config**

Run:

```bash
emacsclient --eval '(progn (find-file "~/dev/jordangarrison/nix-config/users/jordangarrison/tools/doom.d/config.org") (org-babel-tangle) (load-file "~/dev/jordangarrison/nix-config/users/jordangarrison/tools/doom.d/config.el") t)'
```

Expected output:

```text
t
```

- [ ] **Step 5: Verify the replacement keybindings**

Run:

```bash
emacsclient --eval '(list (key-binding (kbd "SPC j a c")) (key-binding (kbd "SPC j a p")) (key-binding (kbd "SPC j a x")) (key-binding (kbd "SPC j a t")) (key-binding (kbd "SPC j a s")) (key-binding (kbd "SPC j a S")) (key-binding (kbd "SPC j a w")))'
```

Expected output:

```text
(jag/agent-vterm-start-or-switch-claude jag/agent-vterm-start-or-switch-pi jag/agent-vterm-start-or-switch-codex jag/agent-vterm-send-region jag/agent-vterm-switch-session jag/agent-vterm-switch-project-session jag/agent-vterm-switch-workspace-session)
```

- [ ] **Step 6: Verify old generic sender is no longer defined after reload**

Run:

```bash
emacsclient --eval '(list (fboundp '\''jag/send-to-vterm) (fboundp '\''jag/send-region-to-vterm))'
```

Expected output after a normal reload may still be `(t t)` if the old functions were already loaded in the long-running Emacs image. If so, restart Emacs or inspect `config.el` instead. The source-level verification must pass:

```bash
rg -n "jag/send-to-vterm|jag/send-region-to-vterm|Send code to vterm" users/jordangarrison/tools/doom.d/config.org users/jordangarrison/tools/doom.d/config.el
```

Expected output:

```text
```

No matches.

- [ ] **Step 7: Commit the keybinding replacement**

```bash
git add users/jordangarrison/tools/doom.d/config.org users/jordangarrison/tools/doom.d/config.el
git commit -m "feat(doom): route agent keys to vterm sessions"
```

Expected result: a commit replacing the primary agent keybindings and removing the obsolete generic vterm sender.

---

### Task 3: Verify region context formatting with live Emacs evaluation

**Files:**
- Modify: `users/jordangarrison/tools/doom.d/config.org` only if a verification issue is found.

- [ ] **Step 1: Create a controlled source buffer and target buffer check**

Run:

```bash
emacsclient --eval '
(with-temp-buffer
  (insert "alpha\nbeta\ngamma\n")
  (write-file "/tmp/jag-agent-vterm-format-test.txt")
  (let ((target (get-buffer-create "*agent:test:claude*")))
    (with-current-buffer target
      (setq-local jag/agent-vterm-agent-name "claude")
      (setq-local jag/agent-vterm-launch-project-root "/tmp/"))
    (buffer-substring-no-properties
     (point-min)
     (point-max))
    (jag/agent-vterm-format-region-context (point-min) (point-max) target)))'
```

Expected output:

```text
"Project root: /tmp\nFile: jag-agent-vterm-format-test.txt\nLines: 1-3\n\nContent:\nalpha\nbeta\ngamma\n"
```

- [ ] **Step 2: Verify outside-root path falls back to absolute path**

Run:

```bash
emacsclient --eval '
(with-temp-buffer
  (insert "outside\n")
  (write-file "/tmp/jag-agent-vterm-outside-test.txt")
  (let ((target (get-buffer-create "*agent:test:codex*")))
    (with-current-buffer target
      (setq-local jag/agent-vterm-agent-name "codex")
      (setq-local jag/agent-vterm-launch-project-root "/home/jordangarrison/dev/jordangarrison/nix-config/"))
    (jag/agent-vterm-format-region-context (point-min) (point-max) target)))'
```

Expected output includes the absolute file path:

```text
"Project root: /home/jordangarrison/dev/jordangarrison/nix-config\nFile: /tmp/jag-agent-vterm-outside-test.txt\nLines: 1-1\n\nContent:\noutside\n"
```

- [ ] **Step 3: Verify no-region behavior is explicit**

Run:

```bash
emacsclient --eval '(condition-case err (call-interactively '\''jag/agent-vterm-send-region) (user-error (error-message-string err)))'
```

Expected output:

```text
"Select a region to send to a vterm agent"
```

- [ ] **Step 4: Fix any formatting failures**

If Step 1 or Step 2 fails, update only the relevant helper in `users/jordangarrison/tools/doom.d/config.org` and tangle/reload again:

```bash
emacsclient --eval '(progn (find-file "~/dev/jordangarrison/nix-config/users/jordangarrison/tools/doom.d/config.org") (org-babel-tangle) (load-file "~/dev/jordangarrison/nix-config/users/jordangarrison/tools/doom.d/config.el") t)'
```

Expected output:

```text
t
```

Then rerun Steps 1 and 2 until both outputs match.

- [ ] **Step 5: Commit any verification fixes**

If Task 3 required source changes, commit them:

```bash
git add users/jordangarrison/tools/doom.d/config.org users/jordangarrison/tools/doom.d/config.el
git commit -m "fix(doom): format vterm agent region context"
```

If Task 3 required no source changes, do not create an empty commit.

---

### Task 4: Verify session lifecycle manually and with safe probes

**Files:**
- Modify: `users/jordangarrison/tools/doom.d/config.org` only if a verification issue is found.

- [ ] **Step 1: Verify CLI executables are available in the user environment**

Run:

```bash
command -v claude
command -v codex
command -v pi
```

Expected output: each command prints an executable path. If one is missing, stop and report which agent cannot be launched on this machine.

- [ ] **Step 2: Verify command registry executable checks**

Run:

```bash
emacsclient --eval '(mapcar (lambda (name) (let ((cmd (jag/agent-vterm--agent-command name))) (list name (car cmd) (and (executable-find (car cmd)) t)))) (jag/agent-vterm--available-agent-names))'
```

Expected output has `t` for each executable:

```text
(("claude" "claude" t) ("codex" "codex" t) ("pi" "pi" t))
```

- [ ] **Step 3: Launch or switch Claude from Emacs**

In the target Doom workspace, invoke:

```text
SPC j a c
```

Expected behavior:

- A vterm buffer named like `*agent:<workspace>:claude*` appears.
- The buffer starts `claude --dangerously-skip-permissions`.
- Running `SPC j a c` again switches to the same buffer instead of creating a duplicate.

- [ ] **Step 4: Launch or switch Codex from Emacs**

Invoke:

```text
SPC j a x
```

Expected behavior:

- A vterm buffer named like `*agent:<workspace>:codex*` appears.
- The buffer starts `codex --yolo`.
- Running `SPC j a x` again switches to the same buffer instead of creating a duplicate.

- [ ] **Step 5: Launch or switch Pi from Emacs**

Invoke:

```text
SPC j a p
```

Expected behavior:

- A vterm buffer named like `*agent:<workspace>:pi*` appears.
- The buffer starts `pi`.
- Running `SPC j a p` again switches to the same buffer instead of creating a duplicate.

- [ ] **Step 6: Verify live session metadata**

Run after launching at least one vterm agent:

```bash
emacsclient --eval '(mapcar (lambda (buffer) (with-current-buffer buffer (list (buffer-name buffer) jag/agent-vterm-agent-name jag/agent-vterm-command jag/agent-vterm-launch-workspace-name jag/agent-vterm-launch-project-root jag/agent-vterm-scope))) (jag/agent-vterm--live-buffers))'
```

Expected output: each launched session has a buffer name, agent name, command list, workspace name or nil, project root, and `workspace` scope. Example:

```text
(("*agent:nix-config:claude*" "claude" ("claude" "--dangerously-skip-permissions") "nix-config" "/home/jordangarrison/dev/jordangarrison/nix-config/" workspace))
```

- [ ] **Step 7: Verify switchers**

Invoke each binding:

```text
SPC j a s
SPC j a S
SPC j a w
```

Expected behavior:

- `SPC j a s` prompts across all live vterm agent sessions.
- `SPC j a S` prompts only for sessions in the current project.
- `SPC j a w` prompts only for sessions in the current Doom workspace.

- [ ] **Step 8: Verify `SPC j a t` pastes without submitting**

In a file-visiting buffer:

1. Select a region.
2. Invoke:

```text
SPC j a t
```

Expected behavior:

- If exactly one vterm agent session exists in the workspace, Emacs selects it automatically.
- If multiple vterm agent sessions exist in the workspace, Emacs prompts for the target.
- If none exist, Emacs prompts for `claude`, `codex`, or `pi`, starts that workspace-local agent, then targets it.
- The target vterm receives an editable prompt, not an automatic submission.
- The pasted text includes `Project root:`, `File:`, `Lines:`, and `Content:` headers.

- [ ] **Step 9: Commit any lifecycle fixes**

If Task 4 required source changes, commit them:

```bash
git add users/jordangarrison/tools/doom.d/config.org users/jordangarrison/tools/doom.d/config.el
git commit -m "fix(doom): stabilize vterm agent sessions"
```

If Task 4 required no source changes, do not create an empty commit.

---

### Task 5: Final repository verification

**Files:**
- No source changes expected.

- [ ] **Step 1: Confirm no package sync is needed**

Run:

```bash
git diff -- users/jordangarrison/tools/doom.d/packages.el users/jordangarrison/tools/doom.d/init.el
```

Expected output:

```text
```

No output. If package declarations changed unexpectedly, stop and explain before running `doom sync`.

- [ ] **Step 2: Confirm generated config contains the new functions**

Run:

```bash
rg -n "jag/agent-vterm-start-or-switch|jag/agent-vterm-send-region|Vterm agent Claude" users/jordangarrison/tools/doom.d/config.org users/jordangarrison/tools/doom.d/config.el
```

Expected output includes matches in both `config.org` and `config.el`.

- [ ] **Step 3: Confirm old generic vterm sender is gone from source**

Run:

```bash
rg -n "jag/send-to-vterm|jag/send-region-to-vterm|Send code to vterm" users/jordangarrison/tools/doom.d/config.org users/jordangarrison/tools/doom.d/config.el
```

Expected output:

```text
```

No matches.

- [ ] **Step 4: Run final keybinding probe**

Run:

```bash
emacsclient --eval '(list (key-binding (kbd "SPC j a c")) (key-binding (kbd "SPC j a p")) (key-binding (kbd "SPC j a x")) (key-binding (kbd "SPC j a t")) (key-binding (kbd "SPC j a s")) (key-binding (kbd "SPC j a S")) (key-binding (kbd "SPC j a w")))'
```

Expected output:

```text
(jag/agent-vterm-start-or-switch-claude jag/agent-vterm-start-or-switch-pi jag/agent-vterm-start-or-switch-codex jag/agent-vterm-send-region jag/agent-vterm-switch-session jag/agent-vterm-switch-project-session jag/agent-vterm-switch-workspace-session)
```

- [ ] **Step 5: Check git status**

Run:

```bash
git status --short
```

Expected output:

```text
```

No output after all implementation commits are created.

## Self-Review

- Spec coverage: Task 1 implements the vterm session architecture, built-in agent registry, workspace-local lifecycle, metadata, selectors, prompt formatting, paste-without-submit, and future profile shape. Task 2 replaces the conflicting keybindings and removes the old generic sender. Tasks 3-5 verify formatting, lifecycle, keybindings, and source cleanliness.
- Placeholder scan: This plan contains no unresolved placeholder markers and no unspecified code steps. Conditional fix steps include exact files, reload commands, and commit messages.
- Type consistency: Function names consistently use the `jag/agent-vterm-*` prefix. Buffer-local metadata names match the design document. Keybinding commands match the functions defined in Task 1 and probed in Tasks 2 and 5.
