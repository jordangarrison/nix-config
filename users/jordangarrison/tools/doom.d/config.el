;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets.
(setq user-full-name "Jordan Garrison"
      user-mail-address "jordan@jordangarrison.dev")

;; Doom exposes five (optional) variables for controlling fonts in Doom. Here
;; are the three important ones:
;;
;; + `doom-font'
;; + `doom-variable-pitch-font'
;; + `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;;
;; They all accept either a font-spec, font string ("Input Mono-12"), or xlfd
;; font string. You generally only need these two:
(setq doom-font (font-spec :family "FiraCode Nerd Font" :size 13 :weight 'semibold))

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-ir-black)

;; doom dashboard configuration
(defun my-dashboard ()
  (let* ((banner '("Emacs"))
         (longest-line (apply #'max (mapcar #'length banner))))
    (put-text-property
     (point)
     (dolist (line banner (point))
       (insert (+doom-dashboard--center
                +doom-dashboard--width
                (concat line (make-string (max 0 (- longest-line (length line))) 32)))
               "\n"))
     'face 'doom-dashboard-banner)))

(setq +doom-dashboard-ascii-banner-fn #'my-dashboard)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
;; (setq org-directory "~/Documents/org")
;; (add-hook! 'org-mode-hook '(lambda () (setq fill-column 100)))
;; (add-hook! 'org-mode-hook #'auto-fill-mode)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

(xterm-mouse-mode 1)
(xclip-mode 1)

;; Here are some additional functions/macros that could help you configure Doom:
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c g k').
;; This will open documentation for it, including demos of how they are used.
;;
;; You can also try 'gd' (or 'C-c g d') to jump to their definition and see how
;; they are implemented.

;;
;; `use-package!' section
;;
;; Tree Sitter
;; (use-package! tree-sitter
;;   :config
;;   (require 'tree-sitter-langs)
;;   (global-tree-sitter-mode)
;;   (add-hook 'tree-sitter-after-on-hook #'tree-sitter-hl-mode))

;;
;;
;; Intelligent Ruby LSP Configuration
;; Automatically detects and uses the best available Ruby LSP server
;;
(defun jag/ruby-lsp-server-available-p (server-command)
  "Check if a Ruby LSP server command is available and working."
  (let ((cmd (if (listp server-command) server-command (list server-command))))
    (condition-case nil
        (and (executable-find (car cmd))
             ;; Test if the command actually works
             (zerop (apply #'call-process (car cmd) nil nil nil 
                           (append (cdr cmd) '("--help")))))
      (error nil))))

(defun jag/detect-ruby-lsp-server ()
  "Detect the best available Ruby LSP server for the current project."
  (cond
   ;; First try bundle exec solargraph (project-specific)
   ((and (file-exists-p "Gemfile")
         (jag/ruby-lsp-server-available-p '("bundle" "exec" "solargraph")))
    '(bundle-solargraph . ("bundle" "exec" "solargraph" "stdio")))
   
   ;; Then try global solargraph
   ((jag/ruby-lsp-server-available-p "solargraph")
    '(solargraph . ("solargraph" "stdio")))
   
   ;; Try ruby-lsp (if available)
   ((and (file-exists-p "Gemfile")
         (jag/ruby-lsp-server-available-p '("bundle" "exec" "ruby-lsp")))
    '(bundle-ruby-lsp . ("bundle" "exec" "ruby-lsp")))
   
   ((jag/ruby-lsp-server-available-p "ruby-lsp")
    '(ruby-lsp . ("ruby-lsp")))
   
   ;; Fall back to typeprof if it's working
   ((jag/ruby-lsp-server-available-p "typeprof")
    ;; Test if typeprof can actually start without dependency errors
    (condition-case nil
        (progn
          (call-process "typeprof" nil nil nil "--version")
          '(typeprof . ("typeprof" "--lsp")))
      (error nil)))
   
   ;; No working LSP server found
   (t nil)))

(after! lsp-mode
  ;; Register our intelligent Ruby LSP client
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection
                     (lambda ()
                       (let ((server-info (jag/detect-ruby-lsp-server)))
                         (if server-info
                             (progn
                               (message "Using Ruby LSP server: %s" (car server-info))
                               (cdr server-info))
                           (error "No working Ruby LSP server found")))))
    :major-modes '(ruby-mode)
    :priority 30  ; Higher priority than default servers
    :server-id 'ruby-intelligent
    :multi-root t
    :initialization-options
    (lambda ()
      (let ((server-info (jag/detect-ruby-lsp-server)))
        (pcase (car server-info)
          ('bundle-solargraph
           (list :diagnostics t :completion t :hover t :formatting t))
          ('solargraph
           (list :diagnostics t :completion t :hover t :formatting t))
          ('bundle-ruby-lsp
           (list :enabledFeatures ["diagnostics" "formatting" "completion" "hover"]))
          ('ruby-lsp
           (list :enabledFeatures ["diagnostics" "formatting" "completion" "hover"]))
          ('typeprof
           (list))
          (_ (list))))))))

;; Configure Ruby mode to use our intelligent LSP and disable problematic ones
(after! ruby-mode
  (add-hook 'ruby-mode-hook
            (lambda ()
              ;; Disable the default typeprof-ls client to prevent conflicts
              (setq-local lsp-disabled-clients '(typeprof-ls))
              ;; Show which LSP server we're using
              (let ((server-info (jag/detect-ruby-lsp-server)))
                (if server-info
                    (message "Ruby LSP: Using %s" (car server-info))
                  (message "Ruby LSP: No working server found")))
              (lsp-deferred))))

;; Just some key bindings
;;
(map! :leader :desc "Expand Region" "e e" #'er/expand-region)
(map! :leader :desc "Find File Other Window" "f o " #'find-file-other-window)
(map! :leader :desc "Switch other Frame" "w f" #'other-frame)
(map! :leader :desc "Maximize Frame" "w m f" #'toggle-frame-maximized)
(map! :leader :desc "Maximize Frame" "w m v" #'toggle-frame-fullscreen)
(map! :leader :desc "Shell command" "j s" #'shell-command)
(map! :leader :desc "Comment line" "j /" #'comment-line)
;; (map! :leader :desc "Go to definition" "j k" #')

;; Little details
(setq-default line-spacing 3)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; open-in-external-app is used to quickly open files and     ;;
;; folders right from the comfort of your emacs home.         ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun open-in-external-app (&optional @fname)
  "Open the current file or dired marked files in external app.
The app is chosen from your OS's preference.

When called in emacs lisp, if @fname is given, open that.

URL `http://ergoemacs.org/emacs/emacs_dired_open_file_in_ext_apps.html'
Version 2019-11-04"
  (interactive)
  (let* (
         ($file-list
          (if @fname
              (progn (list @fname))
            (if (string-equal major-mode "dired-mode")
                (dired-get-marked-files)
              (list (buffer-file-name)))))
         ($do-it-p (if (<= (length $file-list) 5)
                       t
                     (y-or-n-p "Open more than 5 files? "))))
    (when $do-it-p
      (cond
       ((string-equal system-type "windows-nt")
        (mapc
         (lambda ($fpath)
           (w32-shell-execute "open" $fpath)) $file-list))
       ((string-equal system-type "darwin")
        (mapc
         (lambda ($fpath)
           (shell-command
            (concat "open " (shell-quote-argument $fpath))))  $file-list))
       ((string-equal system-type "gnu/linux")
        (mapc
         (lambda ($fpath) (let ((process-connection-type nil))
                            (start-process "" nil "xdg-open" $fpath))) $file-list))))))

(map! :leader :desc "Open in external app" "o o" #'open-in-external-app)
(map! :leader :desc "Kill buffer and delete window" "d d" #'kill-buffer-and-window)

;;
;; Sync my dotfiles
;;
(defun jag/dotfile-sync (&optional commit-message)
  (interactive "sCommit Message: ")
  (message
   (shell-command-to-string
    (concat "~/.dotfiles/scripts/dotfile-sync "
            (shell-quote-argument commit-message)))))
(map! :leader :desc "Sync the dotfiles" "j j" 'jag/dotfile-sync)


;;
;; Change what emacs considers a shell prompt
;;
(setq shell-prompt-pattern '"^[^#$%>\n]*~?[#$%>] *")

;;
;; Projectile
;;
(setq projectile-project-search-path '("~/dev"))
(setq projectile-git-fd-args "-0 -H --color=never --type file --exclude .git --strip-cwd-prefix")

;;
;; Tramp
;;
;; (add-to-list 'tramp-connection-properties
;;              (list (regexp-quote "/ssh:endeavour:")
;;                    "remote-shell" "/run/current-system/sw/bin/zsh"))

;;
;; Python Black Formatter
;;
;; (use-package! python-black
;;   :demand t
;;   :after python)
;; (add-hook! 'python-mode-hook #'python-black-on-save-mode)
;; (map! :leader :desc "Blacken Buffer" "m p b" #'python-black-buffer)
;; (map! :leader :desc "Blacken Region" "m p r" #'python-black-region)
;; (map! :leader :desc "Blacken Statement" "m p s" #'python-black-statement)

;; accept completion from copilot and fallback to company
;;(unless (eq system-type 'darwin)
;;  (use-package! copilot
;;    :hook (prog-mode . copilot-mode)
;;    :bind (("C-TAB" . 'copilot-accept-completion-by-word)
;;           ("C-<tab>" . 'copilot-accept-completion-by-word)
;;           :map copilot-completion-map
;;           ("<tab>" . 'copilot-accept-completion)
;;           ("TAB" . 'copilot-accept-completion)))
;;  (setq! copilot-node-executable "~/.nix-profile/bin/node"))

;; kubernetes
;; (use-package! kubernetes)
;; (use-package! kubernetes-evil
;;   :after kubernetes)

;;
;; JS Prettier mode
;;
(add-hook! 'js2-mode-hook #'prettier-js-mode)
(add-hook! 'web-mode-hook #'prettier-js-mode)
(add-hook! 'typescript-mode-hook #'prettier-js-mode)
(add-hook! 'json-mode-hook #'prettier-js-mode)

;;
;; Vue JS
;;
;; (add-hook! 'vue-mode-hook #'lsp)

;; Ace
(map! :leader :desc "Ace select window" "j w" #'ace-select-window)
(map! :leader :desc "Ace swap window" "j s" #'ace-swap-window)
(map! :leader :desc "Ace delete windows" "j d" #'ace-delete-window)
(map! :leader :desc "Ace delete other windows" "j D" #'ace-delete-other-windows)

;;
;; Toggle themes
;;
(defvar *jag-theme-dark* 'leuven)
(defvar *jag-theme-light* 'doom-ir-dark)
(defvar *jag-current-theme* *jag-theme-dark*)

(defadvice load-theme (before theme-dont-propagate activate)
  "Disable theme before loading new one."
  (mapc #'disable-theme custom-enabled-themes))


(defun jag/next-theme (theme)
  (if (eq theme 'default)
      (disable-theme *jag-current-theme*)
    (progn
      (load-theme theme t)))
  (setq *jag-current-theme* theme))

(defun jag/toggle-theme ()
  (interactive)
  (cond ((eq *jag-current-theme* *jag-theme-dark*) (jag/next-theme *jag-theme-light*))
        ((eq *jag-current-theme* *jag-theme-light*) (jag/next-theme *jag-theme-dark*))))
;; ((eq *jag-current-theme

(map! :leader :desc "Toggle theme" "j t" #'jag/toggle-theme)

(map! :leader :desc "Format buffer" "m j f" #'cider-format-buffer)

(use-package! chatgpt
  :defer t
  :bind ("C-c q" . chatgpt-query))

(setq auth-sources '("~/.authinfo"))

;; (use-package! exercism)

;; gleam
;; (use-package! gleam-ts-mode
;;   :config
;;   ;; setup formatter to be used by `SPC c f`
;;   (after! apheleia
;;     (setf (alist-get 'gleam-ts-mode apheleia-mode-alist) 'gleam)
;;     (setf (alist-get 'gleam apheleia-formatters) '("gleam" "format" "--stdin"))))

(after! treesit
  (add-to-list 'auto-mode-alist '("\\.gleam$" . gleam-ts-mode)))

(after! gleam-ts-mode
  (unless (treesit-language-available-p 'gleam)
    ;; compile the treesit grammar file the first time
    (gleam-ts-install-grammar)))

;; Prevent Emacs from trying to access X11 clipboard
;; (setq x-select-enable-clipboard nil)
;; (setq select-enable-clipboard nil)
