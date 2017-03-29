(in-package :sandbox)


(defparameter vsync? t)

(defparameter *mat4-identity* (cg-matrix:identity-matrix))

(defconstant +single-float-just-less-than-one+ 0.99999997)

(defparameter *16x16-tilemap* (regular-enumeration 16 16))
(defparameter *4x4-tilemap* (regular-enumeration 4 4))

(defun render ()
  (if vsync?
      (window::set-vsync t)
      (window::set-vsync nil))

  (gl:viewport 0 0 e:*width* e:*height*)
  (luse-shader :solidshader)
  (gl:uniform-matrix-4fv
   (gl:get-uniform-location *shader-program* "pmv")
   *mat4-identity*
   nil)

  (progn
    (gl:enable :depth-test)
    (gl:clear-color 0f0 0f0 0f0 0f0)
    (gl:clear
     :color-buffer-bit 
     :depth-buffer-bit)
    )

  (progn
    (bind-shit :font)
    (lcalllist-invalidate :string)
    (let ((scale 32.0))
      (name-mesh :string (lambda ()
			   (gl-draw-quads 
			    (lambda (tex-buf pos-buf lit-buf)
			      (draw-string-raster-char
			       pos-buf tex-buf lit-buf
			       *16x16-tilemap* foo
			       (/ scale e:*width* 2.0)
			       (/ scale e:*height*)
			       -1.0 1.0
			       (- +single-float-just-less-than-one+)))))))
    (ldrawlist :string))

  (window:update-display))

(defun glinnit ()
  (setf %gl:*gl-get-proc-address* (e:get-proc-address))
  (setf *shader-program* nil)
  
  (let ((width (if t 480 854))
	(height (if t 360 480)))
    (window:push-dimensions width height))
  (setf e:*resize-hook* #'on-resize)
 
  (progn    
    (name-shader :solidshader :ss-vs :ss-frag '(("pos" . 0)	
						("col" . 3)
						("tex" . 8)))
    (src-text :ss-vs (shader-path "pos4f-col4f-tex2f.vs"))
    (src-text :ss-frag (shader-path "fcol4f-ftex2f-no0a.frag")))
 
  (progn
    (src-image :font-image (img-path #P"font/codepage-437-vga-9x16-alpha.png"))
    (texture-imagery :font :font-image))
  
  (progn
    (src-image :cursor-image (img-path #P"cursor/windos-cursor.png"))
    (texture-imagery :cursor :cursor-image)))

(defun on-resize (w h)
  (setf *window-height* h
	*window-width* w))


(defun gl-draw-quads (func)
  (let ((iter *attrib-buffer-iterators*))
    (reset-attrib-buffer-iterators iter)
    (let ((pos-buf (aref iter 0))
	  (lit-buf (aref iter 3))
	  (tex-buf (aref iter 8)))
      (let ((times (funcall func tex-buf pos-buf lit-buf)))
	(gl:with-primitives :quads
	  (reset-attrib-buffer-iterators iter)
	  (mesh-test42 times lit-buf tex-buf pos-buf))))))

(defun mesh-test42 (times lit tex pos)
  (declare (type iter-ator:iter-ator tex pos))
  (iter-ator:wasabiis ((d lit)
		       (uv tex)
		       (xyz pos))
    (dotimes (x times)
      (%gl:vertex-attrib-2f 8 (uv) (uv))
      (%gl:vertex-attrib-4f 3 (d) (d) (d) (d))
      (%gl:vertex-attrib-3f 0 (xyz) (xyz) (xyz)) )))

(defun draw-string-raster-char (pos-buf tex-buf lit-buf
				lookup string char-width char-height x y z)
  (declare (type iter-ator:iter-ator pos-buf tex-buf lit-buf)
	   (type single-float x y z char-width char-height)
	   (type simple-vector lookup)
	   (optimize (speed 3) (safety 0))
	   (type (simple-array character) string))
  (iter-ator:wasabios ((epos pos-buf)
		       (etex tex-buf)
		       (elit lit-buf))
    (let ((len (array-total-size string))
	  (times 0))
      (declare (type fixnum times))
      (let ((xoffset x)
	    (yoffset y))
	(declare (type single-float xoffset yoffset))
	(let ((wonine (if nil 0.0 (/ char-width 8.0))))
	  (dotimes (position len)
	    (let ((char (row-major-aref string position)))
	      (let ((next-x (+ xoffset char-width wonine))
		    (next-y (- yoffset char-height)))
		(if (char= char #\Newline)
		    (setf xoffset x
			  yoffset next-y)
		    (progn
		      (unless (char= #\space char)
			(incf times 4)
			(dotimes (x 4)
			  (etouq (ngorp (preach 'elit '(
							(1+ xoffset)
							(- (random 2f0) 1f0)
							(1+ yoffset)
							1f0)))))
			(let ((code (char-code char)))
			  (multiple-value-bind (x0 y0 x1 y1) (index-quad-lookup lookup code)
			    (etouq (ngorp (preach 'etex (duaq 1 nil '(x0 x1 y0 y1)))))))
			(etouq (ngorp
				(preach
				 'epos
				 (quadk+ 'z '(xoffset
					      (- next-x wonine)
					      next-y
					      yoffset))))))
		      (setf xoffset next-x))))))))
      times)))