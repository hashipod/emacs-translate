# emacs-translate

Translate the current buffer via an LLM into a target language; the result is shown in a buffer named **\*Translation-\<current buffer name\>\*** (e.g. `*Translation-main.el*` or `*Translation-*scratch**`).

Three backends, set by `emacs-translate-backend`:

- `claude` (default): runs the Claude Code CLI (`claude -p`). It uses your Claude subscription. No API key.
- `codex`: runs the Codex CLI (`codex exec`). It uses your ChatGPT subscription. No API key.
- `gptel`: uses **[gptel](https://github.com/karthink/gptel)**. Backends, API keys, and models are configured in gptel.

## Features

- **Interactive language choice**: After running the command, a target language list (completing-read) is shown with completion; first item is the default.
- **Default English**: The first item in the list is "English"; press Enter to accept it.
- **Subscription CLIs**: Uses the `claude` or `codex` CLI, so no API key is necessary.
- **gptel integration**: Optional. Uses gptel’s backends (OpenAI, Anthropic, Ollama, etc.) and your existing gptel configuration.

## Install and configure

1. Pick a backend:

   ```elisp
   (setq emacs-translate-backend 'claude)   ; or 'codex, or 'gptel
   ```

   For `claude` or `codex`, install the CLI and log in once. Make sure the CLI is on `exec-path`.
   Change the command with `emacs-translate-claude-command` or `emacs-translate-codex-command`.
   For `gptel`, install **gptel** and set up your backend and API key (see [gptel documentation](https://gptel.org)).

2. Put `emacs-translate.el` on your load-path or add its directory:

   ```elisp
   (add-to-list 'load-path "/path/to/emacs-translate")
   (load "emacs-translate")
   ```

3. For `gptel`: no extra API keys or URLs in this package. Use gptel’s `gptel-backend`, `gptel-model`, `gptel-api-key`, etc.

### gptel setup (configure backend first)

Only for the `gptel` backend. You must **register a backend in your init** (and optionally set it as the default) before `emacs-translate-buffer` and other gptel commands can send requests.

- **Register a backend**: use `gptel-make-anthropic`, `gptel-make-openai`, etc., to create a backend object.
- **Set as default**: `(setq gptel-backend <that-object>)` so all gptel requests (including this package’s translation) use it.
- **API key**: pass it as `:key "your-key"` in `gptel-make-*`, or use `gptel-api-key` / auth-source; see [gptel docs](https://gptel.org).

**Custom / third-party Anthropic-compatible endpoint** (e.g. Zhipu AI; `:host` must be the hostname only—no `https://` or path):

```elisp
(setq gptel-backend
      (gptel-make-anthropic "Claude"
                           :host "open.bigmodel.cn"
                           :endpoint "/api/anthropic/v1/messages"
                           :stream t
                           :models '(claude-sonnet-4-5-20250929)
                           :key "your-api-key"))
```

Adjust `:endpoint` and `:models` to match your provider’s documentation.

**Official Anthropic example**:

```elisp
(setq gptel-backend (gptel-make-anthropic "Claude"
                 :stream t
                 :key "your-anthropic-api-key"))
```

## Usage

- **M-x emacs-translate-buffer**  
  Translate the whole current buffer. You are prompted for the target language (default English). The translation opens in **\*Translation-\<current buffer name\>\*** (view-mode, read-only).

- **M-x emacs-translate-region**  
  Translate only the active region. The result goes to a new buffer; if **\*Translation-\<name\>\*** already exists, names **\*Translation-\<name\>-1\***, **-2\***, … are used.

- **M-x emacs-translate-dwim**  
  Do-what-I-mean: with an active region, translates the region; otherwise translates the whole buffer. Convenient single binding, e.g. `(global-set-key (kbd "C-c C-t") #'emacs-translate-dwim)`.

## Dependencies

- Emacs 27.1+
- `claude` or `codex` CLI, or **gptel** (optional, only for the `gptel` backend)

## Customize language list

Edit `emacs-translate-language-alist`: list of `(display-name . prompt-name)`; first is default:

```elisp
(setq emacs-translate-language-alist
      '(("English" . "English")
        ("Simplified Chinese" . "Simplified Chinese")
        ;; ...
        ))
```
