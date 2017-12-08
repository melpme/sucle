(in-package :sandbox)

(defun draw-world ()
  (declare (optimize (speed 3) (safety 0)))
  (with-hash-table-iterator (next *g/chunk-call-list*)
    (loop
       (multiple-value-bind (more? key value) (next)
	 (declare (ignore key))
	 (unless more? (return nil))
	 (gl:call-list value)))))
(progn
  (defparameter *g/chunk-call-list* (make-hash-table :test 'eq))
  (defun get-chunk-display-list (name)
    (gethash name *g/chunk-call-list*))
  (defun set-chunk-display-list (name list-num)
    (setf (gethash name *g/chunk-call-list*) list-num))
  (defun remove-chunk-display-list (name)
    (remhash name *g/chunk-call-list*)))

(defun update-world-vao (x y z)
  (maphash (lambda (k v)
	     (declare (ignorable k))
	     (gl:delete-lists v 1)
	     (remove-chunk-display-list k))
	   *g/chunk-call-list*)
  (map nil #'dirty-push
       (sort (alexandria:hash-table-keys world::chunkhash) #'< :key
	     (lambda (position)
	       (multiple-value-bind (i j k) (world:unhashfunc position)
		 ((lambda (x0 y0 z0 x1 y1 z1)
		    (let ((dx (- x1 x0))
			  (dy (- y1 y0))
			  (dz (- z1 z0)))
		      (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))
		  x y z
		  (- i 8)
		  (- k 8)
		  (- j 8)))))))

(defun update-chunk-mesh (len coords iter)
  (when coords
    (let ((old-call-list (get-chunk-display-list coords)))     
      (when old-call-list (gl:delete-lists old-call-list 1)))
    (if (zerop len)
	(remove-chunk-display-list coords)	  
	(set-chunk-display-list
	 coords
	 (glhelp:with-gl-list
	   (gl:with-primitives :quads	     
	     (with-vec (a b c) (iter)
	       (flush-my-iterator a
		 (flush-my-iterator b
		   (flush-my-iterator c
		     (mesh-chunk len a b c)))))))))))

(defun mesh-chunk (times a b c)
  (declare (type fixnum times))
  (declare (optimize (speed 3) (safety 0)))
  (iter-ator:bind-iterator-in
   (xyz single-float) a
   (iter-ator:bind-iterator-in
    (uv single-float) b
    (iter-ator:bind-iterator-in
     (dark single-float) c
     (dotimes (x times)
       (%gl:vertex-attrib-3f 2 (xyz) (xyz) (xyz))
       (%gl:vertex-attrib-2f 8 (uv) (uv))
       (%gl:vertex-attrib-1f 0 (dark));;;zero always comes last?
       )))))

(defun attrib-buffer-iterators ()
  (map-into (make-array 3 :element-type t :initial-element nil)
	    (function my-iterator)))

(setf lparallel:*kernel* (lparallel:make-kernel 4))
(defparameter *achannel* (lparallel:make-channel))
(defun designatemeshing ()
  (loop
     (multiple-value-bind (value success-p) (lparallel:try-receive-result *achannel*)
       (if success-p
	   (apply (car value) (cdr value))
	   (return))))
  (let ((thechunk (dirty-pop)))
    (when thechunk
      (let ((lparallel:*task-category* 'mesh-chunk))
	(lparallel:submit-task
	 *achannel*
	 (lambda (iter space)
	   (map nil (lambda (x) (free-my-iterator-memory x)) iter)
	   (multiple-value-bind (a b c) (chunk-shape thechunk iter)
	     (%list space #'update-chunk-mesh a b c)))
	 (attrib-buffer-iterators)
	 (make-list 4))))))

;;;;keeping track of the changes to the world
(progn
  (defparameter dirtychunks (q:make-uniq-q))
  (defun dirty-pop ()
    (q:uniq-pop dirtychunks))
  (defun dirty-push (item)
    (q:uniq-push item dirtychunks))
  (defun block-dirtify (i j k)
    (dirty-push (world:chop (world:chunkhashfunc i k j)))))

(defun setblock-with-update (i j k blockid new-light-value)
  (let ((old-blockid (world:getblock i j k)))
    (when (/= blockid old-blockid)
      (let ((old-light-value (world:getlight i j k)))
	(when (setf (world:getblock i j k) blockid)
	  (when (< new-light-value old-light-value)
	    (de-light-node i j k))
	  (unless (= old-light-value new-light-value)
	    (setf (world:getlight i j k) new-light-value))
	  (sky-de-light-node i j k)
	  (unless (zerop new-light-value)
	    (light-node i j k))
	  (flet ((check (a b c)
		   (light-node (+ i a) (+ j b) (+ k c))
		   (sky-light-node (+ i a) (+ j b) (+ k c))))
	    (check -1 0 0)
	    (check 1 0 0)
	    (check 0 -1 0)
	    (check 0 1 0)
	    (check 0 0 -1)
	    (check 0 0 1))
	  (block-dirtify i j k))))))

(defun plain-setblock (i j k blockid new-light-value &optional (new-sky-light-value 0))
  (when (setf (world:getblock i j k) blockid)
    (setf (world:getlight i j k) new-light-value)
    (setf (world:skygetlight i j k) new-sky-light-value)
    (block-dirtify i j k)))

;;;;;

(defparameter *atest*
  (let (a)
    (setf
     a
     (make-instance
      'glslgen:shader-program-data
      :version 120
      :vs
      (glslgen:make-shader-vars
       :out '((color-out "float")
	      (texcoord-out "vec2"))
       :in '((position "vec4")
	     (texcoord "vec2")
	     (color "float" "0.5")
	     (projection-model-view "mat4"))
       :program
       (glslgen:main
	(glslgen:spaces `("gl_Position" "=" projection-model-view "*" position))
	(glslgen:spaces `(color-out "=" color))
	(glslgen:spaces `(texcoord-out "=" texcoord))))
      :frag
      (glslgen:make-shader-vars
       :in '((texcoord "vec2")
	     (color "float")
	     (sampler "sampler2D")

	     (time "float"))
       :program
       (glslgen:main
	(glslgen:spaces `("vec4" "pixdata" "=" ,(glslgen:funglsl "texture2D"
								 'sampler
								 'texcoord)))
	(glslgen:spaces `((:fragment-color ".rgb") "=" color "*" ("pixdata" ".rgb")))))
      :attributes
      '((position . 2)
	(texcoord . 8)
	(color . 0))
      :varyings
      '((color-out . color)
	(texcoord-out . texcoord))
      :uniforms
      '((:pmv (:vertex-shader projection-model-view)))))
    (glslgen:dump-shader-program-data a)
    a))

(defparameter *save*
  '("#version 100
precision lowp float;
attribute vec4 position;
attribute vec2 texCoord;
attribute float darkness;
uniform mat4 projectionmodelview;
varying vec2 TexCoord;
varying float mycolor;
void main(){
gl_Position = projectionmodelview * position;
mycolor = darkness;
TexCoord = texCoord;
}
"
    "#version 100
precision lowp float;
varying vec2 TexCoord;
varying float mycolor;
uniform sampler2D ourTexture;
void main(){
vec4 texcolor = texture2D(ourTexture, TexCoord);
gl_FragColor.rgb = mycolor * texcolor.rgb;
}
") )