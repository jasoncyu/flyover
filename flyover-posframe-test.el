;;; flyover-posframe-test.el --- Popup backend tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'flyover-posframe)

(defmacro flyover-posframe-test--with-buffer (&rest body)
  "Run BODY in a selected diagnostic buffer with mocked child frames."
  (declare (indent 0) (debug t))
  `(save-window-excursion
     (with-temp-buffer
       (switch-to-buffer (current-buffer))
       (insert "first\nsecond\n")
       (goto-char (point-min))
       (let ((flyover-posframe-mode t)
             (flyover-mode t)
             (flyover-hide-during-completion t)
             (flyover-display-mode 'show-only-on-same-line)
             (shown nil) (hidden 0) (completion nil)
             (diagnostics (list (flyover-error-create :line 1 :column 0
                                                   :level 'error :message "First error")
                                (flyover-error-create :line 2 :column 0
                                                   :level 'warning :message "Second error"))))
         (cl-letf (((symbol-function 'posframe-workable-p) (lambda () t))
                   ((symbol-function 'posframe-show)
                    (lambda (_buffer &rest args) (setq shown (plist-get args :string))))
                   ((symbol-function 'posframe-hide) (lambda (&rest _) (cl-incf hidden)))
                   ((symbol-function 'posframe-delete)
                    (lambda (buffer) (kill-buffer buffer)))
                   ((symbol-function 'flyover--completion-active-p) (lambda () completion))
                   ((symbol-function 'flyover--get-all-errors) (lambda () diagnostics)))
           (unwind-protect (progn ,@body)
             (flyover-posframe--cleanup)))))))

(ert-deftest flyover-posframe-current-line-and-no-overlays ()
  (flyover-posframe-test--with-buffer
    (let ((before (buffer-string)))
      (flyover--maybe-display-errors)
      (should (equal shown "First error"))
      (should-not flyover--overlays)
      (should (equal before (buffer-string)))
      (forward-line)
      (flyover--maybe-display-errors)
      (should (equal shown "Second error"))
      (forward-line)
      (flyover--maybe-display-errors)
      (should (> hidden 0)))))

(ert-deftest flyover-posframe-completion-and-disable-hide ()
  (flyover-posframe-test--with-buffer
    (flyover--maybe-display-errors)
    (setq completion t shown nil)
    (flyover--maybe-display-errors)
    (should-not shown)
    (should (> hidden 0))
    (setq completion nil)
    (flyover--maybe-display-errors)
    (should shown)
    (setq flyover-mode nil)
    (let ((before hidden))
      (flyover--maybe-display-errors)
      (should (> hidden before)))))

(ert-deftest flyover-posframe-request-only ()
  (flyover-posframe-test--with-buffer
    (setq flyover-display-mode 'show-only-on-request)
    (flyover--maybe-display-errors)
    (should-not shown)
    (flyover--display-errors diagnostics)
    (should (equal shown "First error"))
    (setq shown nil)
    (forward-line)
    (flyover--maybe-display-errors)
    (should-not shown)
    (should-not flyover-posframe--requested-line)))

(ert-deftest flyover-posframe-terminal-and-original-backend ()
  (flyover-posframe-test--with-buffer
    (cl-letf (((symbol-function 'posframe-workable-p) (lambda () nil)))
      (flyover--maybe-display-errors)
      (should-not shown))
    (let ((flyover-posframe-mode nil) called)
      (flyover-posframe--display (lambda (errors) (setq called errors)) diagnostics)
      (should (eq called diagnostics)))))

(ert-deftest flyover-posframe-cleanup ()
  (flyover-posframe-test--with-buffer
    (flyover--maybe-display-errors)
    (let ((popup flyover-posframe--buffer))
      (should (buffer-live-p popup))
      (flyover-posframe--cleanup)
      (should-not (buffer-live-p popup))
      (should-not flyover-posframe--buffer))))

(provide 'flyover-posframe-test)
;;; flyover-posframe-test.el ends here
