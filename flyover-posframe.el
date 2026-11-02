;;; flyover-posframe.el --- Floating diagnostic display for Flyover -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Flyover contributors
;; SPDX-License-Identifier: MIT
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (flyover "0.9.9") (posframe "1.4.0"))

;;; Commentary:
;; Enable `flyover-posframe-mode' alongside `flyover-mode' for a floating
;; diagnostic display.  Requires posframe and a graphical Emacs frame.
;; Automatic display shows diagnostics on the current line; with
;; `flyover-display-mode' set to show-only-on-request, use
;; `flyover-flash-error-at-point'.  Other overlay visibility policies do
;; not apply to this backend.

;;; Code:

(require 'flyover)
(require 'posframe)

(defvar-local flyover-posframe-mode nil)
(defvar-local flyover-posframe--buffer nil)
(defvar-local flyover-posframe--requested-line nil)

(defun flyover-posframe--hide (&rest _)
  "Hide this buffer's diagnostic popup."
  (when (buffer-live-p flyover-posframe--buffer)
    (posframe-hide flyover-posframe--buffer)))

(defun flyover-posframe--cleanup ()
  "Delete this buffer's popup and child frame."
  (when (buffer-live-p flyover-posframe--buffer)
    (posframe-delete flyover-posframe--buffer))
  (setq flyover-posframe--buffer nil
        flyover-posframe--requested-line nil))

(defun flyover-posframe--show (errors)
  "Show ERRORS for the current line without creating overlays."
  (let ((messages
         (delq nil
               (mapcar
                (lambda (err)
                  (when (and (= (flyover-error-line err) (line-number-at-pos))
                             (memq (flyover--normalize-level (flyover-error-level err))
                                   flyover-levels))
                    (propertize
                     (flyover--format-message-with-id
                      (flyover--remove-checker-name (flyover-error-message err)) err)
                     'face (flyover--get-face
                            (flyover--normalize-level (flyover-error-level err))))))
                (flyover--filter-errors errors)))))
    (if (and messages (posframe-workable-p)
             (eq (window-buffer (selected-window)) (current-buffer))
             (not (and flyover-hide-during-completion
                       (flyover--completion-active-p))))
        (progn
          (unless (buffer-live-p flyover-posframe--buffer)
            (setq flyover-posframe--buffer
                  (generate-new-buffer " *flyover-posframe*")))
          (posframe-show
           flyover-posframe--buffer
           :string (mapconcat #'identity messages "\n")
           :position (point)
           :max-width (max 20 (min flyover-max-line-length
                                  (- (window-width) 4)))
           :internal-border-width 1
           :left-fringe 8 :right-fringe 8
           :accept-focus nil
           :hidehandler #'posframe-hidehandler-when-buffer-switch))
      (flyover-posframe--hide))))

(defun flyover-posframe--display (original &optional errors)
  "Use popup rendering instead of ORIGINAL for ERRORS when enabled."
  (if (not flyover-posframe-mode)
      (funcall original errors)
    (when (eq flyover-display-mode 'show-only-on-request)
      (setq flyover-posframe--requested-line (line-number-at-pos)))
    (flyover-posframe--show (or errors (flyover--get-all-errors)))))

(defun flyover-posframe--maybe-display (original &rest args)
  "Update the popup, or call ORIGINAL with ARGS."
  (if (not flyover-posframe-mode)
      (apply original args)
    (if (or (not flyover-mode)
            (and (eq flyover-display-mode 'show-only-on-request)
                 (not (eql flyover-posframe--requested-line
                           (line-number-at-pos)))))
        (progn
          (setq flyover-posframe--requested-line nil)
          (flyover-posframe--hide))
      (flyover-posframe--show (flyover--get-all-errors)))))

;;;###autoload
(define-minor-mode flyover-posframe-mode
  "Display Flyover diagnostics in a floating child frame.
Automatic display follows the current line.  The on-request policy is
also supported.  Requires a graphical frame; terminal frames show no popup."
  :lighter nil
  (flyover--clear-overlays)
  (if flyover-posframe-mode
      (progn
        (add-hook 'post-command-hook #'flyover--cursor-display-debounced nil t)
        (add-hook 'kill-buffer-hook #'flyover-posframe--cleanup nil t)
        (add-hook 'change-major-mode-hook #'flyover-posframe--cleanup nil t)
        (add-hook 'after-change-functions #'flyover-posframe--hide nil t)
        (flyover--maybe-display-errors))
    (remove-hook 'after-change-functions #'flyover-posframe--hide t)
    (remove-hook 'kill-buffer-hook #'flyover-posframe--cleanup t)
    (remove-hook 'change-major-mode-hook #'flyover-posframe--cleanup t)
    (when (eq flyover-display-mode 'always)
      (remove-hook 'post-command-hook #'flyover--cursor-display-debounced t))
    (flyover-posframe--cleanup)
    (when flyover-mode
      (setq flyover--last-cursor-line nil)
      (flyover--maybe-display-errors))))

(defun flyover-posframe--restore ()
  "Restore the popup after completion ends."
  (when flyover-posframe-mode
    (flyover--maybe-display-errors)))

(advice-add 'flyover--display-errors :around #'flyover-posframe--display)
(advice-add 'flyover--maybe-display-errors :around #'flyover-posframe--maybe-display)
(advice-add 'flyover--clear-overlays :after #'flyover-posframe--hide)
(advice-add 'flyover--hide-overlays-for-completion :after #'flyover-posframe--hide)
(advice-add 'flyover--show-overlays-after-completion :after
            #'flyover-posframe--restore)

(provide 'flyover-posframe)
;;; flyover-posframe.el ends here
