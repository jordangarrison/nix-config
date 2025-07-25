;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el

;; To install a package with Doom you must declare them here, run 'doom sync' on
;; the command line, then restart Emacs for the changes to take effect.
;; Alternatively, use M-x doom/reload.
;;
;; WARNING: Disabling core packages listed in ~/.emacs.d/core/packages.el may
;; have nasty side-effects and is not recommended.


;; All of Doom's packages are pinned to a specific commit, and updated from
;; release to release. To un-pin all packages and live on the edge, do:
                                        ;(unpin! t)

;; ...but to unpin a single package:
                                        ;(unpin! pinned-package)
;; Use it to unpin multiple packages
                                        ;(unpin! pinned-package another-pinned-package)


;; To install SOME-PACKAGE from MELPA, ELPA or emacsmirror:
                                        ;(package! some-package)
;; (package! elfeed)
;;(package! puppet-mode)
;; (package! flymake-puppet)
;; (add-to-list 'auto-mode-alist '("\\.pp$" . puppet-mode))
;; (add-hook! 'puppet-mode-hook #'(lambda () (flymake-puppet-load)))
;; (package! org-super-agenda)
;; (package! kubernetes)
;; (package! kubernetes-evil)
;; (package! python-black)
;; (package! org-jira)
(package! prettier-js)
;; (package! nvm)
;; (package! vue-mode)
(package! xclip)

;; Tree sitter
;; (package! tree-sitter)
;; (package! tree-sitter-langs)

;; To install a package directly from a particular repo, you'll need to specify
;; a `:recipe'. You'll find documentation on what `:recipe' accepts here:
;; https://github.com/raxod502/straight.el#the-recipe-format
                                        ;(package! another-package
                                        ;  :recipe (:host github :repo "username/repo"))

;; If the package you are trying to install does not contain a PACKAGENAME.el
;; file, or is located in a subdirectory of the repo, you'll need to specify
;; `:files' in the `:recipe':
                                        ;(package! this-package
                                        ;  :recipe (:host github :repo "username/repo"
                                        ;           :files ("some-file.el" "src/lisp/*.el")))

;; If you'd like to disable a package included with Doom, for whatever reason,
;; you can do so here with the `:disable' property:
                                        ;(package! builtin-package :disable t)

;; You can override the recipe of a built in package without having to specify
;; all the properties for `:recipe'. These will inherit the rest of its recipe
;; from Doom or MELPA/ELPA/Emacsmirror:
                                        ;(package! builtin-package :recipe (:nonrecursive t))
                                        ;(package! builtin-package-2 :recipe (:repo "myfork/package"))

;; Specify a `:branch' to install a package from a particular branch or tag.
;; This is required for some packages whose default branch isn't 'master' (which
;; our package manager can't deal with; see raxod502/straight.el#279)
                                        ;(package! builtin-package :recipe (:branch "develop"))

;; (unless (eq system-type 'darwin)
;;   (package! copilot
;;     :recipe (:host github :repo "copilot-emacs/copilot.el" :files ("*.el"))))


(package! git-link
  :recipe (:host github :repo "sshaw/git-link"))


;; (package! projectile :pin "d24b8173223fd0e10ecd4b5e0cfa676dfc3b90c4")

(package! chatgpt
  :recipe (:host github :repo "joshcho/ChatGPT.el" :files ("dist" "*.el")))

(package! org-readwise
  :recipe (:type git :host sourcehut :repo "gloatingfiddle/org-readwise" :files ("*.el") :branch "main"))

(package! sqlite3)

(package! vcl-mode)

;; (package! exercism)

;; (package! gleam-ts-mode
;;   :recipe (:host github
;;            :repo "gleam-lang/gleam-mode"
;;            :branch "main"
;;            :files ("gleam-ts-*.el")))
