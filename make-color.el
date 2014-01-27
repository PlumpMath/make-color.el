;;; make-color.el --- Update fg/bg color of a text sample by pressing r/g/b/... keys

;; Copyright (C) 2014 Alex Kost

;; Author: Alex Kost <alezost@gmail.com>
;; Created: 9 Jan 2014
;; Version: 0.3
;; URL: http://github.com/alezost/make-color.el
;; Keywords: color

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package allows to find a color by pressing keys for smooth
;; changing foreground/background color of any text sample.

;; To manually install the package, copy this file to a directory from
;; `load-path' and add the following to your init-file:
;;
;;   (autoload 'make-color "make-color" nil t)
;;   (autoload 'make-color-switch-to-buffer "make-color" nil t)

;; Usage: select any region and call "M-x make-color".  You will see a
;; buffer in `make-color-mode'.  Select some text in it and press "n" to
;; set this text for colorizing.  Now you can modify a color with the
;; following keys:
;;
;;   - r/R, g/G, b/B - decrease/increase red, green, blue components
;;   - c/C, m/M, y/Y - decrease/increase cyan, magenta, yellow components
;;   - h/H, s/S, l/L - decrease/increase hue, saturation, luminance
;;   - RET - change current color (prompt for a value)

;; If you are satisfied with current color, press "k" to put the color
;; into `kill-ring'.  Any time you can set a new probing region with
;; "n".  Also you can switch between modifying background/foreground
;; colors with "t".  See mode description ("C-h m") for other key
;; bindings.

;; Buffer in `make-color-mode' is not read-only, so you can yank and
;; delete text and undo the changes as you always do.

;; For full description, see <http://github.com/alezost/make-color.el>.

;;; Code:

(require 'color)
(require 'cl-macs)

(defgroup make-color nil
  "Find suitable color by modifying a text sample."
  :group 'faces)

(defcustom make-color-shift-step 0.02
  "Step of shifting a component of the current color.
Should be a floating number from 0.0 to 1.0."
  :type 'float
  :group 'make-color)

(defcustom make-color-sample
  "Neque porro quisquam est qui dolorem ipsum quia dolor sit amet
consectetur adipisci velit.
                                         Marcus Tullius Cicero"
  "Default text sample used for probing a color.
See also `make-color-sample-beg' and `make-color-sample-end'."
  :type 'string
  :group 'make-color)

(defcustom make-color-sample-beg 133
  "Start position of text in `make-color-sample' for probing a color.
If nil, start probing text from the beginning of the sample."
  :type '(choice integer (const nil))
  :group 'make-color)

(defcustom make-color-sample-end 154
  "End position of text in `make-color-sample' for probing a color.
If nil, end probing text in the end of the sample."
  :type '(choice integer (const nil))
  :group 'make-color)

(defcustom make-color-buffer-name "*Make Color*"
  "Default name of the make-color buffer."
  :type 'string
  :group 'make-color)

(defcustom make-color-use-single-buffer t
  "If nil, create a new make-color buffer for each `make-color' call.
If non-nil, use only one make-color buffer."
  :type 'boolean
  :group 'make-color)

(defcustom make-color-show-color t
  "If non-nil, show message in minibuffer after changing current color."
  :type 'boolean
  :group 'make-color)

(defcustom make-color-face-keyword :foreground
  "Default face parameter for colorizing."
  :type '(choice
          (const :tag "Foreground" :foreground)
          (const :tag "Background" :background))
  :group 'make-color)

(defcustom make-color-new-color-after-region-change t
  "What color should be used after changing the probing region.
If nil, current color stays the same.
If non-nil, current color is set to the color of the probing region."
  :type 'boolean
  :group 'make-color)

(defcustom make-color-get-color-function
  'make-color-get-color-at-pos
  "Function used for getting a color of a character.
Should accept 2 arguments: a symbol or keyword
`foreground'/`background' and a point position."
  :type 'function
  :group 'make-color)

(defcustom make-color-set-color-function
  'make-color-set-color
  "Function used for setting a color of a region.
Should accept 4 arguments:
  - symbol or keyword `foreground'/`background',
  - color - a list (R G B) of float numbers from 0.0 to 1.0,
  - position of the beginning of region,
  - position of the end of region."
  :type 'function
  :group 'make-color)

(defvar make-color-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-j" 'newline)
    (define-key map "\C-m" 'make-color-set-current-color)
    (define-key map "n" 'make-color-set-probing-region)
    (define-key map "p" 'make-color-set-step)
    (define-key map "f" 'make-color-use-foreground)
    (define-key map "d" 'make-color-use-background)
    (define-key map "t" 'make-color-toggle-face-parameter)
    (define-key map "k" 'make-color-current-color-to-kill-ring)
    (define-key map "F" 'make-color-foreground-color-to-kill-ring)
    (define-key map "D" 'make-color-background-color-to-kill-ring)
    (define-key map "u" 'undo)
    (define-key map "q" 'bury-buffer)
    map)
  "Keymap containing make-color commands.")


;;; Changing colors

(defun make-color-+ (nums &optional overlap)
  "Return sum of float numbers from 0.0 to 1.0 from NUMS list.
Returning value is always between 0.0 and 1.0 inclusive.
If OVERLAP is non-nil and the sum exceeds the limits, oh god i
can't formulate it, look at the code."
  (let ((res (apply #'+ nums)))
    (if overlap
        (let ((frac (- res (truncate res))))
          (if (> frac 0)
              frac
            (+ 1 frac)))
      (color-clamp res))))

(cl-defun make-color-shift-color-by-rgb
    (color &key (red 0) (green 0) (blue 0))
  "Return RGB color by modifying COLOR with RED/GREEN/BLUE.
COLOR and returning value are lists in a form (R G B).
RED/GREEN/BLUE are numbers from 0.0 to 1.0."
  (list (make-color-+ (list (car      color) red))
        (make-color-+ (list (cadr     color) green))
        (make-color-+ (list (cl-caddr color) blue))))

(cl-defun make-color-shift-color-by-hsl
    (color &key (hue 0) (saturation 0) (luminance 0))
  "Return RGB color by modifying COLOR with HUE/SATURATION/LUMINANCE.
COLOR and returning value are lists in a form (R G B).
HUE/SATURATION/LUMINANCE are numbers from 0.0 to 1.0."
  (let ((hsl (apply 'color-rgb-to-hsl color)))
    (color-hsl-to-rgb
     (make-color-+ (list (car      hsl) hue) 'overlap)
     (make-color-+ (list (cadr     hsl) saturation))
     (make-color-+ (list (cl-caddr hsl) luminance)))))


;;; Shifting current color

(defvar make-color-current-color nil
  "Current color - a list in a form (R G B).")

(defmacro make-color-define-shift-function
  (name direction sign-fun color-fun key &rest components)
  "Define function for shifting current color.
Function name is `make-color-DIRECTION-NAME'.

NAME is a unique part of function name like \"red\" or \"hue\".
Can be a string or a symbol.

DIRECTION is a string used in the name and
description (\"increase\" or \"decrease\").

SIGN-FUN is a function used for direction of shifting (`+' or `-').

COLOR-FUN is a function used for modifying current color
\(`make-color-shift-color-by-rgb' or
`make-color-shift-color-by-hsl').

If KEY is non-nil, a binding with KEY will be defined in
`make-color-mode-map'.

Each component from COMPONENTS list is one of the keywords
accepted by COLOR-FUN.  Specified COMPONENTS of the current color
will be shifted by the defined function."
  (let* ((fun-name (intern (format "make-color-%s-%s" direction name)))
         (fun-doc (concat (format "%s %s component of the current color by VAL."
                                  (capitalize direction) name)
                          "\nIf VAL is nil, use `make-color-shift-step'."))
         (fun-def
          `(defun ,fun-name (&optional val)
             ,fun-doc
             (interactive)
             (let ((color
                    (apply ,color-fun
                           (or make-color-current-color '(0 0 0))
                           (cl-mapcan
                            (lambda (elt)
                              (list elt
                                    (if val
                                        (funcall ,sign-fun val)
                                      (funcall ,sign-fun make-color-shift-step))))
                            ',components))))
               (make-color-update-sample color)))))
    (if key
        `(progn ,fun-def (define-key make-color-mode-map ,key ',fun-name))
      fun-def)))

(defmacro make-color-define-shift-functions (model name key &rest components)
  "Define functions for increasing/decreasing current color.

Define 2 functions: `make-color-increase-NAME' and
`make-color-decrease-NAME' with optional argument VAL.

MODEL is a string \"rgb\" or \"hsl\" for choosing
`make-color-shift-color-by-rgb' or `make-color-shift-color-by-hsl'.

KEY should be nil or a string of one letter.  If KEY is non-nil,
bindings for defined functions will be defined in
`make-color-mode-map'.  Up-case letter will be used for increasing
function, down-case letter - for decreasing function.

For other args, see `make-color-define-shift-function'."
  (let ((shift-fun (intern (concat "make-color-shift-color-by-" model))))
    `(progn
       (make-color-define-shift-function
        ,name "increase" #'+ #',shift-fun ,(upcase key) ,@components)
       (make-color-define-shift-function
        ,name "decrease" #'- #',shift-fun ,(downcase key) ,@components))))

(make-color-define-shift-functions "rgb" "red"        "r" :red)
(make-color-define-shift-functions "rgb" "green"      "g" :green)
(make-color-define-shift-functions "rgb" "blue"       "b" :blue)
(make-color-define-shift-functions "rgb" "cyan"       "c" :green :blue)
(make-color-define-shift-functions "rgb" "magenta"    "m" :blue  :red)
(make-color-define-shift-functions "rgb" "yellow"     "y" :red   :green)

(make-color-define-shift-functions "hsl" "hue"        "h" :hue)
(make-color-define-shift-functions "hsl" "saturation" "s" :saturation)
(make-color-define-shift-functions "hsl" "luminance"  "l" :luminance)


;;; MakeColor buffers

;;;###autoload
(defun make-color-switch-to-buffer (&optional arg)
  "Switch to make-color buffer or create one.
With prefix, make a new make-color buffer unconditionally."
  (interactive "P")
  (let ((bufs (make-color-get-buffers))
        buf)
    (if (or arg (null bufs))
        (make-color)
      ;; delete current make-color buffer from `bufs'
      (when (eq major-mode 'make-color-mode)
        (setq bufs (delete (current-buffer) bufs)))
      (cond
       ((null bufs)
        (message "This is a single make-color buffer."))
       ((null (cdr bufs))   ; there is only one non-current buffer
        (setq buf (car bufs)))
       (t
        (setq buf (completing-read "MakeColor buffer: "
                                   (mapcar #'buffer-name bufs)
                                   nil t))))
      (when buf
        (let ((win (get-buffer-window buf)))
          (if win
              (select-window win)
            (pop-to-buffer-same-window (get-buffer buf))))))))

(defun make-color-get-buffers ()
  "Return a list of make-color buffers."
  (let ((re (regexp-quote make-color-buffer-name)))
    (cl-remove-if-not
     (lambda (buf) (string-match re (buffer-name buf)))
     (buffer-list))))

(defun make-color-get-buffer (&optional clear)
  "Return make-color buffer.
If CLEAR is non-nil, delete contents of the buffer.
If `make-color-use-single-buffer' is nil, create a new buffer,
otherwise return an existing one."
  (let ((buf (get-buffer-create
              (if make-color-use-single-buffer
                  make-color-buffer-name
                (generate-new-buffer-name make-color-buffer-name)))))
    (when clear
      (with-current-buffer buf (erase-buffer)))
    buf))


;;; Getting and setting faces

;; Original `foreground-color-at-point' and `background-color-at-point'
;; don't understand faces with property lists of face attributes (see
;; (info "(elisp) Special Properties")).  For example, if a face was set
;; by `facemenu-set-foreground'/`facemenu-set-background' the original
;; functions return nil, so we need some code for getting a color.

(defun make-color-set-color (param color beg end)
  "Set color of the text between BEG and END.
Param is a symbol or keyword `foreground' or `background'.
COLOR should be a list in a form (R G B)."
  (facemenu-add-face (list (list (make-color-keyword param) color))
                     beg end))

(defun make-color-get-color-from-face-spec (param spec)
  "Return color from face specification SPEC.
PARAM is a keyword `:foreground' or `:background'.
SPEC can be a face name, a property list of face attributes or a
list of any level of nesting containing face names or property
lists.
Returning value is a string: either a color name or a hex value.
If PARAM is not found in SPEC, return nil."
  (cond
   ((facep spec)
    (face-attribute-specified-or (face-attribute spec param nil t)
                                 nil))
   ((listp spec)
    (if (keywordp (car spec))
        (plist-get spec param)
      (let (res)
        (cl-loop for elt in spec
                 do (setq res (make-color-get-color-from-face-spec
                               param elt))
                 until res)
        res)))
   (t
    (message "Ignoring unknown face specification '%s'." spec)
    nil)))

(defun make-color-get-color-at-pos (param &optional pos)
  "Return color of a character at position POS.
PARAM is a symbol or keyword `foreground' or `background'.
If POS is not specified, use current point positiion."
  (let ((param (make-color-keyword param))
        (faceprop (get-char-property (or pos (point)) 'face)))
    (or (and faceprop
             (make-color-get-color-from-face-spec param faceprop))
        ;; if color was not found, use default face
        (face-attribute 'default param))))

(defun make-color-foreground-color-at-point ()
  "Return foreground color of the character at point."
  (make-color-get-color-at-pos :foreground (point)))

(defun make-color-background-color-at-point ()
  "Return background color of the character at point."
  (make-color-get-color-at-pos :background (point)))


;;; UI

(defvar make-color-probing-region-bounds nil
  "Cons cell of start and end positions of a probing text.")

(define-derived-mode make-color-mode nil "MakeColor"
  "Major mode for making color.

\\{make-color-mode-map}"
  (make-local-variable 'make-color-current-color)
  (make-local-variable 'make-color-probing-region-bounds)
  (make-local-variable 'make-color-shift-step)
  (make-local-variable 'make-color-face-keyword))

(defun make-color-check-mode (&optional buffer)
  "Raise error if BUFFER is not in `make-color-mode'.
If BUFFER is nil, use current buffer."
  (with-current-buffer (or buffer (current-buffer))
    (or (eq major-mode 'make-color-mode)
        (error "Current buffer should be in make-color-mode"))))

(defun make-color-keyword (symbol)
  "Return a keyword same as SYMBOL but with leading `:'.
If SYMBOL is a keyword, return it."
  (if (keywordp symbol)
      symbol
    (make-symbol (concat ":" (symbol-name symbol)))))

(defun make-color-unkeyword (kw)
  "Return a symbol same as keyword KW but without leading `:'."
  (or (keywordp kw)
      (error "Symbol `%s' is not a keyword" kw))
  (make-symbol (substring (symbol-name kw) 1)))

(defun make-color-update-sample (color &optional buffer)
  "Update current color and text sample in the BUFFER with COLOR.
COLOR should be a list in a form (R G B).
If BUFFER is nil, use current buffer."
  (make-color-check-mode buffer)
  (with-current-buffer (or buffer (current-buffer))
    (if make-color-probing-region-bounds
        ;; if bounds are nils, use the whole sample
        (let ((beg (or (car make-color-probing-region-bounds)
                       (point-min)))
              (end (or (cdr make-color-probing-region-bounds)
                       (point-max))))
          (setq make-color-current-color color
                color (apply 'color-rgb-to-hex color))
          (funcall make-color-set-color-function
                   make-color-face-keyword color beg end)
          (and make-color-show-color
               (message "Current color: %s" color)))
      (make-color-set-probing-region))))

;;;###autoload
(defun make-color ()
  "Begin to make color by modifying a text sample.
If region is active, use it as the sample."
  (interactive)
  ;; `sample' is the whole text yanking in make-color buffer;
  ;; `region' is a part of this text used for colorizing
  (cl-multiple-value-bind (sample region)
      (if (region-active-p)
          (list (buffer-substring (region-beginning) (region-end))
                nil)
        (list make-color-sample
              (cons make-color-sample-beg make-color-sample-end)))
    (pop-to-buffer-same-window (make-color-get-buffer 'clear))
    (make-color-mode)
    (insert sample)
    (goto-char (point-min))
    (setq-local make-color-probing-region-bounds region)
    (make-color-update-current-color-maybe)))

(defun make-color-set-step (step)
  "Set `make-color-shift-step' to a value STEP.
Interactively, prompt for STEP."
  (interactive
   (list (read-number "Set step to: " make-color-shift-step)))
  (if (and (floatp step)
           (>= 1.0 step)
           (<= 0.0 step))
      (setq make-color-shift-step step)
    (error "Should be a value from 0.0 to 1.0")))

(defun make-color-set-probing-region ()
  "Use current region for colorizing."
  (interactive)
  (make-color-check-mode)
  (if (region-active-p)
      (progn (setq make-color-probing-region-bounds
                   (cons (region-beginning) (region-end)))
             (make-color-update-current-color-maybe)
             (deactivate-mark)
             (message "The region was set for color probing."))
    (if (y-or-n-p (concat "No active region. Use the whole sample for colorizing?"))
        (progn (setq make-color-probing-region-bounds (cons nil nil))
               (make-color-update-current-color-maybe))
      ;; TODO do not hard-code "n"
      (message "Select a region for colorizing and press \"n\"."))))

(defun make-color-set-current-color ()
  "Set current color to the prompted value and update probing region."
  (interactive)
  (let ((color (read-color
                (concat "Color"
                        (and make-color-current-color
                             (format " (current: %s)"
                                     (apply 'color-rgb-to-hex
                                            make-color-current-color)))
                        ": "))))
    (unless (string= color "")
      (make-color-update-sample (color-name-to-rgb color)))))

(defun make-color-update-current-color-maybe ()
  "Update current color if needed.
See `make-color-new-color-after-region-change'."
  (when make-color-new-color-after-region-change
    (setq
     make-color-current-color
     (color-name-to-rgb
      (save-excursion
        (goto-char (or (car make-color-probing-region-bounds)
                       0))
        (make-color-get-color-at-pos make-color-face-keyword))))))

(defun make-color-use-foreground ()
  "Set foreground as the parameter for further changing."
  (interactive)
  (setq-local make-color-face-keyword :foreground)
  (make-color-update-current-color-maybe)
  (message "Foreground has been set for colorizing."))

(defun make-color-use-background ()
  "Set background as the parameter for further changing."
  (interactive)
  (setq-local make-color-face-keyword :background)
  (make-color-update-current-color-maybe)
  (message "Background has been set for colorizing."))

(defun make-color-toggle-face-parameter ()
  "Switch between setting foreground and background."
  (interactive)
  (if (equal make-color-face-keyword :foreground)
      (make-color-use-background)
    (make-color-use-foreground)))

(defun make-color-to-kill-ring (color)
  "Add color value of COLOR to the `kill-ring'.
COLOR can be a string (color name or a hex value) or a list in a
form (R G B)."
  (when (listp color)
    (setq color (apply 'color-rgb-to-hex color)))
  (kill-new color)
  (message "Color '%s' has been put into kill-ring." color))

(defun make-color-current-color-to-kill-ring ()
  "Add current color to the `kill-ring'."
  (interactive)
  (or make-color-current-color
      (error "make-color-current-color is nil"))
  (make-color-to-kill-ring make-color-current-color))

;;;###autoload
(defun make-color-foreground-color-to-kill-ring ()
  "Add foreground color at point to the `kill-ring'."
  (interactive)
  (make-color-to-kill-ring (make-color-foreground-color-at-point)))

;;;###autoload
(defun make-color-background-color-to-kill-ring ()
  "Add background color at point to the `kill-ring'."
  (interactive)
  (make-color-to-kill-ring (make-color-background-color-at-point)))

(provide 'make-color)

;;; make-color.el ends here
