;;; emacs-translate.el --- Translate buffer to target language via LLM  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Seki Rocc
;; Version: 0.2.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: translate, llm, tools
;; URL: https://github.com/sekirocc/emacs-translate

;;; Commentary:

;; Translate the current buffer via LLM to a target language; show the result
;; in a new buffer.  M-x emacs-translate-buffer, or bind a key to it.
;;
;; Set `emacs-translate-backend' to pick the LLM:
;; - `claude': the Claude Code CLI ("claude -p"), uses your subscription.
;; - `codex': the Codex CLI ("codex exec"), uses your subscription.
;; - `gptel': gptel (configure gptel-backend, gptel-model and an API key).
;;
;; The translation is shown in a buffer named "*Translation-<current buffer name>*".

;;; Code:

(declare-function gptel-request "gptel")

(defgroup emacs-translate nil
  "Translate buffer content via LLM."
  :group 'tools
  :prefix "emacs-translate-")

(defcustom emacs-translate-language-alist
  '(("English" . "English")
    ("Simplified Chinese" . "Simplified Chinese")
    ("Traditional Chinese" . "Traditional Chinese")
    ("Japanese" . "Japanese")
    ("Korean" . "Korean")
    ("French" . "French")
    ("German" . "German")
    ("Spanish" . "Spanish")
    ("Russian" . "Russian")
    ("Arabic" . "Arabic")
    ("Portuguese" . "Portuguese")
    ("Italian" . "Italian"))
  "Target languages: (display name . name for prompt).  First is default."
  :type '(repeat (cons (string :tag "Display name") (string :tag "Prompt name")))
  :group 'emacs-translate)

(defcustom emacs-translate-backend 'claude
  "LLM backend for translation."
  :type '(choice (const :tag "Claude Code CLI" claude)
                 (const :tag "Codex CLI" codex)
                 (const :tag "gptel" gptel))
  :group 'emacs-translate)

(defcustom emacs-translate-claude-command
  '("claude" "-p" "--tools" "" "--no-session-persistence")
  "Command for the `claude' backend.  The prompt goes to stdin."
  :type '(repeat string)
  :group 'emacs-translate)

(defcustom emacs-translate-codex-command
  '("codex" "exec" "--skip-git-repo-check" "-")
  "Command for the `codex' backend.  The prompt goes to stdin."
  :type '(repeat string)
  :group 'emacs-translate)

(defun emacs-translate--buffer-name ()
  "Return the translation buffer name for the current buffer."
  (format "*Translation-%s*" (buffer-name)))

(defun emacs-translate--unique-buffer-name (base)
  "Return a buffer name based on BASE that does not yet exist.
If BASE is taken, try BASE-1, BASE-2, ... (inserting before the final \"*\")."
  (let ((name base)
        (n 0))
    (while (get-buffer name)
      (setq n (1+ n))
      (setq name (replace-regexp-in-string "\\*$" (format "-%d*" n) base)))
    name))

(defun emacs-translate--read-language ()
  "Let user choose target language; return prompt name.
Default is first (English)."
  (let* ((choices (mapcar #'car emacs-translate-language-alist))
         (default (car choices))
         (selected (completing-read
                    (format "Target language (default %s): " default)
                    choices nil t nil nil default)))
    (alist-get selected emacs-translate-language-alist nil nil #'string=)))

(defun emacs-translate--build-prompt (text target-lang)
  "Build translation prompt for TEXT and TARGET-LANG."
  (format "Translate the following into %s.  Output only the translated text, no explanation, title, or quotes.  Preserve paragraphs and line breaks.\n\n%s"
          target-lang text))

(defun emacs-translate--show (response result-buf-name source-mode target-lang)
  "Show RESPONSE in buffer RESULT-BUF-NAME with SOURCE-MODE.
TARGET-LANG is for the message only."
  (let ((buf (get-buffer-create result-buf-name)))
    (with-current-buffer buf
      (delay-mode-hooks (funcall source-mode))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (string-trim response)))
      (goto-char (point-min))
      (set-buffer-file-coding-system 'utf-8)
      (view-mode 1))
    (display-buffer buf)
    (message "Translation done -> %s" target-lang)))

(defun emacs-translate--cli-request (command prompt callback)
  "Run COMMAND with PROMPT on stdin.
Call CALLBACK with stdout on success, or nil on failure."
  (let* ((out (generate-new-buffer " *emacs-translate-out*"))
         (err (generate-new-buffer " *emacs-translate-err*"))
         (proc (make-process
                :name "emacs-translate"
                :buffer out
                :stderr err
                :command command
                :coding 'utf-8
                :connection-type 'pipe
                :noquery t
                :sentinel
                (lambda (p _event)
                  (unless (process-live-p p)
                    (let ((ok (zerop (process-exit-status p))))
                      (unless ok
                        (message "emacs-translate: %s failed: %s" (car command)
                                 (string-trim (with-current-buffer err (buffer-string)))))
                      (funcall callback
                               (and ok (with-current-buffer out (buffer-string))))
                      (kill-buffer out)
                      (kill-buffer err)))))))
    (process-send-string proc prompt)
    (process-send-eof proc)))

(defun emacs-translate--request (text result-buf-name source-mode target-lang)
  "Send translation request for TEXT to TARGET-LANG.
Put result in buffer RESULT-BUF-NAME with SOURCE-MODE."
  (message "Translating to %s via %s ..." target-lang emacs-translate-backend)
  (let ((prompt (emacs-translate--build-prompt text target-lang))
        (callback (lambda (response)
                    (if (not response)
                        (message "Translation request failed")
                      (emacs-translate--show response result-buf-name source-mode target-lang)))))
    (pcase emacs-translate-backend
      ('claude (emacs-translate--cli-request emacs-translate-claude-command prompt callback))
      ('codex (emacs-translate--cli-request emacs-translate-codex-command prompt callback))
      ('gptel
       (require 'gptel)
       (gptel-request prompt
         :callback (lambda (response _info) (funcall callback response))))
      (_ (user-error "Unknown emacs-translate-backend: %S" emacs-translate-backend)))))

;;;###autoload
(defun emacs-translate-buffer (&optional target-lang)
  "Translate current buffer to TARGET-LANG.
Show result in *Translation-<buffer name>*.
If TARGET-LANG is nil, prompt for target language (default: English).
See `emacs-translate-backend' for the LLM."
  (interactive)
  (unless target-lang
    (setq target-lang (emacs-translate--read-language)))
  (let ((text (buffer-substring-no-properties (point-min) (point-max))))
    (if (string-blank-p (string-trim text))
        (user-error "Current buffer is empty")
      (emacs-translate--request text (emacs-translate--buffer-name) major-mode target-lang))))

;;;###autoload
(defun emacs-translate-region (start end &optional target-lang)
  "Translate the region between START and END to TARGET-LANG.
Show the result in a new buffer.  If a buffer with the default name
already exists, use *Translation-<name>-1*, *Translation-<name>-2*, etc.
If TARGET-LANG is nil, prompt for target language (default: English)."
  (interactive "r")
  (unless (and start end (< start end))
    (user-error "No region selected"))
  (let ((text (buffer-substring-no-properties start end)))
    (if (string-blank-p (string-trim text))
        (user-error "Region is empty")
      (unless target-lang
        (setq target-lang (emacs-translate--read-language)))
      (emacs-translate--request text
                                (emacs-translate--unique-buffer-name (emacs-translate--buffer-name))
                                major-mode
                                target-lang))))

;;;###autoload
(defun emacs-translate-dwim (&optional target-lang)
  "Translate buffer or region to TARGET-LANG (Do What I Mean).
If the region is active and non-empty, translate only the region.
Otherwise translate the whole buffer.
If TARGET-LANG is nil, prompt for target language (default: English)."
  (interactive)
  (if (use-region-p)
      (let ((start (region-beginning))
            (end (region-end)))
        (when (>= start end)
          (user-error "No region selected"))
        (emacs-translate-region start end target-lang))
    (emacs-translate-buffer target-lang)))

(provide 'emacs-translate)
;;; emacs-translate.el ends here
