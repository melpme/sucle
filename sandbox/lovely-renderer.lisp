(in-package :sandbox)

;;non-generic rendering

;;vaohash holds all the vaos which correlate to each chunk
(defparameter vaohash (make-hash-table :test #'equal))
(defparameter shaderhash (make-hash-table :test #'equal))
(defmacro toggle (a)
  `(setf ,a (not ,a)))
(defparameter drawmode nil)

(defun leresize (option)
  (out:push-dimensions option)
  (gl:viewport 0 0 out:width out:height))

(defun ease (x target fraction)
  (+ x (* fraction (- target x))))

(defun render ()
  "responsible for rendering the world"
  (let ((camera (getworld "player")))
    (gl:clear :color-buffer-bit :depth-buffer-bit)
    (if isprinting
	(setf (simplecam-fov camera)
	      (ease (simplecam-fov camera) 90 0.2))
	(setf (simplecam-fov camera)
	      (ease (simplecam-fov camera) 70 0.2))) 
    (setupmatrices camera)
    (sortdirtychunks camera)
    (designatemeshing)
    (settime)
    (if (in:key-pressed-p #\v)
	(progn (leresize t)))
    (if (in:key-pressed-p #\g)
	(update-world-vao))
    (if (in:key-pressed-p #\y)
	(loadblockshader))
    (if (in:key-pressed-p #\q)
	(progn
	  (toggle drawmode)
	  (if drawmode
	      (gl:polygon-mode :front-and-back :line)
	      (gl:polygon-mode :front-and-back :fill))))
    (draw-chunk-meshes)
    (gl:flush)))

(defun draw-chunk-meshes ()
  (gl:enable :depth-test)
  (gl:disable :blend)
  (gl:enable :cull-face)
  (gl:cull-face :back)
  (gl:blend-func :src-alpha :one-minus-src-alpha)
  (gl:active-texture :texture0)
  (bind-shit "terrain.png")
  (use-program "blockshader")
  (set-matrix "model" (mat:identity-matrix))
  (maphash
   (lambda (key vao)
     (declare (ignore key))
     (draw-vao vao))
   vaohash))

(defun designatemeshing ()
  (if (string= mesherwhere? "worker")
      (if (mesherthreadbusy)
	  (progn)
	  (progn
	    (if mesher-thread
		(getmeshersfinishedshit))
	    (let ((achunk (car vox::dirtychunks)))
	      (if achunk
		  (progn
		    (giveworktomesherthread achunk)
		    (setf vox::dirtychunks
			  (delete achunk vox::dirtychunks :test #'equal)))))))
      (let ((achunk (pop vox::dirtychunks)))
	(if achunk
	    (setf (gethash achunk vaohash)
		  (shape-vao (chunk-shape (first achunk)
					  (second achunk)
					  (third achunk))))))))

(defun setupmatrices (camera)
  (set-matrix "view"
	      (mat:easy-lookat
	       (mat:add (mat:onebyfour
			 (list 0
			       (if isneaking (- 1.5 1/8) 1.5)
			       0 0))
			(simplecam-pos camera))
	       (simplecam-pitch camera)
	       (simplecam-yaw camera)))
  (set-matrix "projection"
	      (mat:projection-matrix
	       (deg-rad (simplecam-fov camera))
	       (/ out::pushed-width out::pushed-height) 0.01 128)) )

(defun sortdirtychunks (camera)
  (progn
    (setf dirtychunks
	  (remove nil
		  (sort
		   dirtychunks
		   (lambda (a b)
		     (<
		      (distoplayer a (simplecam-pos camera))
		      (distoplayer b (simplecam-pos camera)))))))))

(defparameter mesherwhere? (if t "worker" "main"))

(defun getmeshersfinishedshit ()
  (multiple-value-bind (coords shape) (sb-thread:join-thread mesher-thread)
    (if coords
	(if shape
	    (setf (gethash coords vaohash) (shape-vao shape))
	    (progn
	      (pushnew coords vox::dirtychunks :test #'equal)))))
  (setf mesher-thread nil))

(defun mesherthreadbusy ()
  (not (or (eq nil mesher-thread)
	   (not (sb-thread:thread-alive-p mesher-thread)))))

(defun giveworktomesherThread (thechunk)
  (setf mesher-thread
	(sb-thread:make-thread
	 (lambda (achunk)
	   (sb-thread:return-from-thread
	    (values
	     achunk
	     (chunk-shape (first achunk)
			  (second achunk)
			  (third achunk)))))
	 :arguments (list thechunk))))

(defun settime ()
  (set-float "timeday" daytime)
  (setnight daytime))

(defun setnight (val)
  (let ((a (lightstuff val)))
    (gl:clear-color  
     (* a 0.68)
     (* a 0.8)
     (* a 1.0) 1.0)
    (set-vec4 "fogcolor"
	      (vector
	       (* a 0.68)
	       (* a 0.8)
	       (* a 1.0) 1.0))))

(defun lightstuff (num)
  (expt 0.8 (- 15 (* 15  num))))

(defparameter mesher-thread nil)

(defun distoplayer (keys pos)
  (hypot
   (diff (scalis keys 16) (mat-lis pos))))

(defun mat-lis (mat)
  (let ((thelist nil))
    (dotimes (x 3)
       (push (row-major-aref mat x) thelist))
    (nreverse thelist)))

(defun diff (a b)
  (mapcar (function -) a b))

(defun scalis (liz s)
  (mapcar (lambda (x) (* x s)) liz))

(defun hypot (list)
  (sqrt (apply (function +) (mapcar (lambda (x) (* x x)) list))))

(defun update-world-vao ()
  "updates all of the vaos in the chunkhash. takes a long time"
  (maphash
   (lambda (k v)
     (declare (ignore v))
     (pushnew (vox::unchunkhashfunc k) vox::dirtychunks :test #'equal))
   vox::chunkhash))

(defmacro progno (&rest nope))

(defun use-program (name)
  (let ((ourprog (gethash name shaderhash)))
    (setq shaderProgram ourprog)
    (gl:use-program ourprog)))

(defun load-a-shader (name vs frag attribs)
  (setf (gethash name shaderhash)
	(load-and-make-shader
	 vs
	 frag
	 attribs)))

(defun glinnit ()
  "initializing things"
  (loadletextures)
  (load-into-texture-library "items.png")
  (load-into-texture-library "grasscolor.png")
  (load-into-texture-library "foliagecolor.png")
  (load-into-texture-library "terrain.png")
  (bind-shit "terrain.png")
  (setf dirtychunks nil)
  (setf mesher-thread nil)
  (clrhash vaohash)
  (clrhash shaderhash)
  (loadblockshader)
  (use-program "blockshader"))

(defun load-into-texture-library (name &optional (othername name))
  (let ((thepic (gethash name picture-library)))
    (if thepic
	(let ((dims (array-dimensions thepic)))
	    (load-shit
	     (fatten thepic)
	     othername (first dims) (second dims))))))

(defun loadblockshader ()
  (load-a-shader
   "blockshader"
   "transforms.vs"
   "basictexcoord.frag"
   '(("position" . 0)
     ("texCoord" . 2)
     ("color" . 4)
     ("blockLight" . 8)
     ("skyLight" . 9))))

(defun sizeof (type-keyword)
  "gets the size of a foreign c type"
  (cffi:foreign-type-size type-keyword))

(defun rad-deg (rad)
  "converts radians to degrees"
  (* rad 180 (/ 1 pi)))
(defun deg-rad (deg)
  "converts degrees to radians"
  (* deg pi 1/180))

(defstruct simplecam
  (pos (mat:onebyfour '(0.0 0.0 0.0 1)))
  (up (mat:onebyfour '(0.0 1.0 0.0 0)))
  (yaw 0)
  (pitch 0)
  (fov 100))

(defparameter shaderProgram nil)

(defun set-matrix (name matrix)
  "sets a uniform matrix"
  (gl:uniform-matrix-4fv
   (gl:get-uniform-location shaderProgram name)
   (mat:to-flat matrix)))

(defun set-int (name thenumber)
  "sets a uniform integer"
  (gl:uniformi
   (gl:get-uniform-location shaderProgram name)
   thenumber))

(defun set-vec4 (name thevec4)
  "sets a uniform integer"
  (gl:uniformfv
   (gl:get-uniform-location shaderProgram name)
   thevec4))

(defun set-float (name thefloat)
  "sets a uniform integer"
  (gl:uniformf
   (gl:get-uniform-location shaderProgram name)
   thefloat))

(defun load-and-make-shader (vpath fpath attribs)
  "loads a shader from a filepath and puts it into a program"
  (make-shader-program-from-strings
   (load-shader-file vpath)
   (load-shader-file fpath)
   attribs))

(defun glActiveTexture (num)
  "sets the active texture"
  (gl:active-texture (+ num (get-gl-constant :texture0))))

(defun get-gl-constant (keyword)
  "gets a gl-constant"
  (cffi:foreign-enum-value '%gl:enum keyword))

(defstruct vao
  id
  length
  verts
  indices)

(defun squish (the-list type &key (biglength (length the-list)))
  "turns a list of identical vertices/indicis into a flat array for opengl"
  (let* ((siz (length (car the-list)))
	 (verts (make-array (* siz biglength) :element-type type))
	 (counter 0))
    (dolist (vert the-list)
      (dotimes (item siz)
	(setf (aref verts counter) (elt vert item))
	(incf counter)))
    verts))

(defun shape-vao (s)
  "converts a shape into a vao"
  (create-vao
   (shape-vs s)
   (shape-is s)))

(defun to-gl-array (seq type
                    &key
                      (length (length seq))
                      (array (gl:alloc-gl-array type length)))
  "writes an array for opengl usage"
  (declare (optimize speed))
  (time
   (let ((pointer (gl::gl-array-pointer array)))
     (print length)
     (dotimes (i length)
       (setf (cffi:mem-aref pointer type i) (row-major-aref seq i)))))
  array)

(defun to-gl-array-uint (seq
			 &key
			 (length (length seq))
			 (array (gl:alloc-gl-array :unsigned-int length)))
  "writes an array for opengl usage"
  (declare (optimize speed))
  (let ((pointer (gl::gl-array-pointer array)))
    (dotimes (i length)
      (setf (cffi:mem-aref pointer :unsigned-int i) (row-major-aref seq i))))
  array)

(defun to-gl-array-float (seq
			  &key
			  (length (length seq))
			  (array (gl:alloc-gl-array :float length)))
  "writes an array for opengl usage"
  (declare (optimize speed))
  (let ((pointer (gl::gl-array-pointer array)))
    (dotimes (i length)
      (setf (cffi:mem-aref pointer :float i) (row-major-aref seq i))))
  array)

(defun destroy-vao (vao)
  "currently unused function to destroy vaos which are done"
  (gl:delete-vertex-arrays (list (vao-id vao))))

(defun create-vao (vertices indices)
  "creates a vao from a list of vertices and indices"
  (let ((vertex-array-object (gl:gen-vertex-array))
	(glverts (to-gl-array-float vertices))
	(glindices (to-gl-array-uint indices)))
    (gl:bind-vertex-array vertex-array-object)
     
    (gl:bind-buffer :array-buffer (gl:gen-buffer))
    (gl:buffer-data :array-buffer :static-draw
		    glverts)
    (gl:bind-buffer :element-array-buffer (gl:gen-vertex-array))
    (gl:buffer-data :element-array-buffer :static-draw
		    glindices) 

    (let ((totsize (* 11 (sizeof :float))))
      (gl:vertex-attrib-pointer
       0 3 :float :false totsize 0)
      (gl:enable-vertex-attrib-array 0)

      (gl:vertex-attrib-pointer
       2 2 :float :false totsize (* 3 (sizeof :float)))
      (gl:enable-vertex-attrib-array 2)

      (gl:vertex-attrib-pointer
       4 4 :float :false totsize (* 5 (sizeof :float)))
      (gl:enable-vertex-attrib-array 4)

      (gl:vertex-attrib-pointer
       8 1 :float :false totsize (* 9 (sizeof :float)))
      (gl:enable-vertex-attrib-array 8)

      (gl:vertex-attrib-pointer
       9 1 :float :false totsize (* 10 (sizeof :float)))
      (gl:enable-vertex-attrib-array 9))
    
    (gl:free-gl-array glverts)
    (gl:free-gl-array glindices)

    (gl:bind-vertex-array 0)
    (make-vao
     :id vertex-array-object
     :length (length indices)
     :verts glverts
     :indices glindices)))

(defun draw-vao (some-vao)
  "draws a vao struct"
  (gl:bind-vertex-array (vao-id some-vao))
  (gl:draw-elements
   :triangles
   (gl:make-null-gl-array :unsigned-int)
   :count (vao-length some-vao))
  (gl:bind-vertex-array 0))

(defun create-texture-wot (tex-data width height)
  "creates an opengl texture from data"
  (let ((the-shit (car (gl:gen-textures 1))))
    (gl:bind-texture :texture-2d the-shit)
    (gl:tex-parameter :texture-2d :texture-min-filter :nearest)
    (gl:tex-parameter :texture-2d :texture-mag-filter :nearest)
    (gl:tex-parameter :texture-2d :texture-wrap-s :clamp-to-edge)
    (gl:tex-parameter :texture-2d :texture-wrap-t :clamp-to-edge)
    (gl:tex-parameter :texture-2d :texture-border-color '(0 0 0 0))
    (gl:tex-image-2d
     :texture-2d 0
     :rgba width height 0 :rgba :unsigned-byte tex-data)
    (gl:generate-mipmap :texture-2d)
    the-shit))

(defun bind-shit (name)
  "bind a texture located in the texture library"
  (let ((num (gethash name texture-library)))
    (gl:bind-texture :texture-2d num)))

(defun make-shader-program-from-strings
    (vertex-shader-string fragment-shader-string attribs)
  "makes a shader program from strings. makes noises if something goes wrong"
  (block nil
    (let ((vertexShader (gl:create-shader :vertex-shader))
	  (fragmentShader (gl:create-shader :fragment-shader))
	  (shaderProgram (gl:create-program)))
      (dolist (val attribs)
	(gl:bind-attrib-location shaderProgram
				 (cdr val)
				 (car val)))
      (gl:shader-source vertexShader vertex-shader-string)
      (gl:compile-shader vertexShader)
      (let ((success (gl:get-shader-info-log vertexShader)))
	(unless (zerop (length success))
	  (return (print success))))
      (gl:shader-source fragmentShader fragment-shader-string)
      (gl:compile-shader fragmentShader)
      (let ((success (gl:get-shader-info-log fragmentShader)))
	(unless (zerop (length success))
	  (return (print success))))
      (gl:attach-shader shaderProgram vertexShader)
      (gl:attach-shader shaderProgram fragmentShader)
      (gl:link-program shaderProgram)
      (let ((success (gl:get-program-info-log shaderProgram)))
	(unless (zerop (length success))
	  (return (print success))))
      (gl:delete-shader vertexShader)
      (gl:delete-shader fragmentShader)
      shaderProgram)))


;;to add to a shape, we push the vertices to the front of the
;;vertex list and the indices to the index list, but we
;;increase the indices by the vertlength amount.

(defstruct shape
  (is (make-array 0 :adjustable t :fill-pointer 0))
  (vs (make-array 0 :adjustable t :fill-pointer 0))
  (vertlength 0)
  (indexlength 0))

(defun destroy-shape (leshape)
  (setf (fill-pointer (shape-is leshape)) 0)
  (setf (fill-pointer (shape-vs leshape)) 0)
  (setf (shape-vertlength leshape) 0)
  (setf (shape-indexlength leshape) 0)
  leshape)

(defun tringulate (verts)
  "take some verts and make a polygon instead"
  (let ((len (length verts)))
    (make-shape
     :is (let ((tris nil))
	   (dotimes (n (- len 2))
	     (push
	      (list
	       0
	       (+ 1 n)
	       (+ 2 n))
	      tris))
	   tris)
     :vs (nreverse verts)
     :indexlength (- len 2)
     :vertlength len)))

(defun add-shape (s1 small2 &key (target s1))
  "merge two shapes into one"
  (let ((new-2-indices
	 (let ((offset (shape-vertlength s1))
	       (ans nil))
	   (dolist (x (shape-is small2))
	     (push
	      (list
	       (+ offset (first x))
	       (+ offset (second x))
	       (+ offset (third x)))
	      ans))
	   ans)))
    (setf (shape-vs target) (append (shape-vs small2) (shape-vs s1))
	  (shape-is target) (append new-2-indices (shape-is s1))
	  (shape-vertlength target) (+ (shape-vertlength s1) (shape-vertlength small2))
	  (shape-indexlength target) (+ (shape-indexlength s1) (shape-indexlength small2)))
    target))

(defun add-verts (s1 verts)
  "add vertices to a shape, expanding it"
  (let* ((len (length verts))
	 (offset (shape-vertlength s1)))
    (dotimes (n (- len 2))
      (vector-push-extend offset (shape-is s1))
      (vector-push-extend (+ n 1 offset) (shape-is s1))
      (vector-push-extend (+ n 2 offset) (shape-is s1)))
    (incf (shape-vertlength s1) len)
    (incf (shape-indexlength s1) (- len 2))
    (dolist (v verts)
      (dotimes (n (length v))
	(let ((indivdata (aref v n)))
	  (dotimes (q (length indivdata))
	    (vector-push-extend (aref indivdata q) (shape-vs s1))))))
    s1))

(in-package :sandbox)

;;i- i+ j- j+ k- k+

(defmacro progno (&rest args) (declare (ignore args)))
(defparameter blockfaces
  (vector
   (lambda ()
     (list
      (vertex
       (pos -0.5 -0.5 -0.5) (uv 0.0 0.0) (opgray 0.6) (blocklight) (skylight))
      (vertex
       (pos -0.5 -0.5  0.5)  (uv 1.0 0.0) (opgray 0.6) (blocklight) (skylight))
      (vertex
       (pos -0.5  0.5  0.5)  (uv 1.0 1.0) (opgray 0.6) (blocklight) (skylight))
      (vertex
       (pos -0.5  0.5 -0.5) (uv 0.0 1.0) (opgray 0.6) (blocklight) (skylight))))
   (lambda () 
     (list
      (vertex
       (pos 0.5 -0.5 -0.5)  (uv 0.0 0.0) (opgray 0.6) (blocklight) (skylight))
      (vertex
       (pos 0.5  0.5 -0.5)  (uv 0.0 1.0) (opgray 0.6) (blocklight) (skylight))
      (vertex
       (pos 0.5  0.5  0.5)  (uv 1.0 1.0) (opgray 0.6) (blocklight) (skylight))
      (vertex
       (pos 0.5 -0.5  0.5)  (uv 1.0 0.0) (opgray 0.6) (blocklight) (skylight))))
   (lambda ()
     (list
      (vertex
       (pos -0.5 -0.5 -0.5)  (uv 0.0 0.0) (opgray 0.5) (blocklight) (skylight))
      (vertex
       (pos 0.5 -0.5 -0.5)  (uv 1.0 0.0)  (opgray 0.5) (blocklight) (skylight))
      (vertex
       (pos 0.5 -0.5  0.5)  (uv 1.0 1.0)  (opgray 0.5) (blocklight) (skylight))
      (vertex
       (pos -0.5 -0.5  0.5)  (uv 0.0 1.0) (opgray 0.5) (blocklight) (skylight))))
   (lambda ()
     (list
      (vertex
       (pos -0.5 0.5 -0.5) (uv 0.0 0.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos -0.5 0.5 0.5) (uv 0.0 1.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos 0.5 0.5 0.5) (uv 1.0 1.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos 0.5 0.5 -0.5) (uv 1.0 0.0) (opgray 1.0) (blocklight) (skylight))))
   (lambda ()
     (list
      (vertex
       (pos -0.5 -0.5 -0.5) (uv 0.0 0.0) (opgray 0.8) (blocklight) (skylight))
      (vertex
       (pos -0.5 0.5 -0.5) (uv 0.0 1.0) (opgray 0.8)(blocklight) (skylight))
      (vertex
       (pos 0.5 0.5 -0.5) (uv 1.0 1.0) (opgray 0.8) (blocklight) (skylight))
      (vertex
       (pos 0.5 -0.5 -0.5) (uv 1.0 0.0) (opgray 0.8) (blocklight) (skylight))))
   (lambda ()
     (list
      (vertex
       (pos -0.5 -0.5  0.5)  (uv 0.0 0.0)(opgray 0.8) (blocklight) (skylight))
      (vertex
       (pos 0.5 -0.5  0.5)  (uv 1.0 0.0) (opgray 0.8) (blocklight) (skylight))
      (vertex
       (pos 0.5  0.5  0.5)  (uv 1.0 1.0) (opgray 0.8)(blocklight) (skylight))
      (vertex
       (pos -0.5  0.5  0.5)  (uv 0.0 1.0) (opgray 0.8) (blocklight) (skylight))))))

(defun skylight ()
  (vector 0.0))
(defun blocklight ()
  (vector 0.0))
(defun opgray (val)
  (rgba val val val 1.0))
(defun vertex (&rest args)
  (make-array (length args) :initial-contents args))
(defun rgba (r g b a)
  (vector r g b a))
(defun pos (x y z)
  (vector x y z))
(defun uv (u v)
  (vector u v))

;;current layout: 3 position floats, 2 texcoord floats, 4 color floats

(defun increment-verts (x y z verts)
  "linear translation of vertices"
  (dolist (n verts)
    (let ((pos (elt n 0)))
      (incf (aref pos 0) x)
      (incf (aref pos 1) y)
      (incf (aref pos 2) z)))
  verts)

(defun fuck-verts (r g b a verts)
  (dolist (n verts)
    (let ((color (elt n 2)))
      (incf (aref color 0) r)
      (incf (aref color 1) g)
      (incf (aref color 2) b)
      (incf (aref color 3) a)))
  verts)

(defun cunt-verts (r g b a verts)
  (dolist (n verts)
    (cunt-vert r g b a (elt n 2)))
  verts)

(defun cunt-vert (r g b a n)
  "colorize a vertex"
  (setf (aref n 0) (* (aref n 0) r))
  (setf (aref n 1) (* (aref n 1) g))
  (setf (aref n 2) (* (aref n 2) b))
  (setf (aref n 3) (* (aref n 3) a))
  n)

(defun %damn-fuck (verts num)
  "converts 0-1 texcoords to terrain.png coords"
  (let* ((xtrans (mod num 16))
	 (ytrans (- 15 (/ (- num xtrans) 16))))
    (dolist (vim verts)
      (let ((v (elt vim 1)))
	(setf (aref v 0) (+ (/ (aref v 0) 16) (/ xtrans 16)))
	(setf (aref v 1) (+ (/ (aref v 1) 16) (/  ytrans 16)))))
    verts))

(defparameter shapebuffer (make-shape))

(defmacro dorange ((var start length) &rest body)
  (let ((temp (gensym))
	(temp2 (gensym))
	(tempstart (gensym))
	(templength (gensym)))
    `(block nil
       (let* ((,templength ,length)
	      (,tempstart ,start)
	      (,var ,tempstart))
	 (declare (type signed-byte ,var))
	 (tagbody
	    (go ,temp2)
	    ,temp
	    (tagbody ,@body)
	    (psetq ,var (1+ ,var))
	    ,temp2
	    (unless (>= ,var (+ ,tempstart ,templength)) (go ,temp))
	    (return-from nil (progn nil)))))))



(defun chunk-shape (io jo ko)
  "turn a chunk into a shape, complete
with positions, textures, and colors. no normals"
  (let* ((new-shape (destroy-shape shapebuffer)))
    (dorange
     (i (* io 16) 16)
     (dorange
      (j (* jo 16) 16)
      (dorange
       (k (* ko 16) 16)
       (let ((blockid (vox::getblock i j k)))
	 (if (not (zerop blockid))
	     (let ((fineshape
		    (blockshape
		     io jo ko
		     blockid
		     (lambda (a b c)
		       (vox::getblock (+ a i) (+ b j) (+ c k)))
		     (lambda (a b c)
		       (vox::getlight (+ a i) (+ b j) (+ c k)))
		     (lambda (a b c)
		       (vox::skygetlight (+ a i) (+ b j) (+ c k))) )))
	       (dolist (face (coerce (delete nil fineshape) 'list))
		 (increment-verts i j k face))
	       (reduce
		#'add-verts
		fineshape
		:initial-value new-shape)))))))
    new-shape))

(defun blockshape (i j k blockid getempty betlight getskylightz)
  (let ((faces
	 (case (aref mc-blocks::getrendertype blockid)
	   (0 (renderstandardblock blockid getempty betlight getskylightz))
	   (1 (renderblockreed blockid i j k betlight getskylightz))
	   (t (make-array 6 :initial-element nil)))))
  
    (if (= blockid 2)
	(let ((ourfunc (aref mc-blocks::getblocktexture blockid)))
	  (dotimes (n 6)
	    (let ((newvert (aref faces n)))
	      (%damn-fuck newvert (funcall ourfunc n)))))
	(let ((the-skin (aref mc-blocks::blockIndexInTexture blockid)))
	  (dotimes (n (length faces))
	    (let ((newvert (aref faces n)))
	      (%damn-fuck newvert the-skin)))))
    (let ((colorizer (aref mc-blocks::colormultiplier blockid)))
      (if (functionp colorizer)
	  (if (= 2 blockid)
	      (let ((face (elt faces 1)))
		(colorize face (funcall colorizer)))
	      (dotimes (n (length faces))
		(let ((face (elt faces n)))
		  (colorize face (funcall colorizer)))))))
    faces))

(eval-when (:load-toplevel :compile-toplevel :execute)
  (defun meep (n)
    (let ((position nil)
	  (val nil))
      (multiple-value-bind (a b) (floor n 2)
	(setf val (if (zerop b)
		      -1
		      1))
	(setf position (mod (- 1 a) 3)))
      (list position val)))

  (defun moop (n)
    (let* ((posses (list 0 0 0))
	   (vals (meep n))
	   (wowee (vector 0 1 2))
	   (pair (vector 2 3 0 1 4 5))
	   (position (first vals)))
      (setf (elt posses  position) (second vals))
      (setf wowee (concatenate 'list (remove position wowee) (vector position)))
      (list* n posses wowee (elt pair n) vals))))

(defmacro drawblockface (side)
  (let ((vals (moop side)))
    (let ((a (second vals))
	  (b (third vals)))
      `(let ((blockidnexttome (funcall getempty ,@a)))
	 (if
	  (or
	   (zerop blockidnexttome)
	   (and (not (aref mc-blocks::opaquecubelooukup blockidnexttome))
		(not (= blockid blockidnexttome))))
	  (let ((newvert (funcall (elt blockfaces ,(fourth vals)))))
	    (lightvert2 newvert betlight ,@b getskylightz)
	    (setf (aref faces ,side) newvert)))))))

(defmacro actuallywow ()
  (let ((tot (list 'progn)))
    (dotimes (n 6)
      (push (list 'drawblockface n) tot))
    (nreverse tot)))

(defun renderstandardblock (blockid getempty betlight getskylightz)
  (let* ((faces (make-array 6 :initial-element nil)))
    (actuallywow)
    faces))

(defparameter xfaces
  (vector
   (lambda ()
     (list
      (vertex
       (pos -0.5 -0.5 -0.5) (uv 0.0 0.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos  0.5 -0.5  0.5)  (uv 1.0 0.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos  0.5  0.5  0.5)  (uv 1.0 1.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos -0.5  0.5 -0.5) (uv 0.0 1.0) (opgray 1.0) (blocklight) (skylight))))
   (lambda () 
     (list
      (vertex
       (pos -0.5 -0.5 -0.5)  (uv 0.0 0.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos -0.5  0.5 -0.5)  (uv 0.0 1.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos 0.5  0.5  0.5)  (uv 1.0 1.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos 0.5 -0.5  0.5)  (uv 1.0 0.0) (opgray 1.0) (blocklight) (skylight))))
   (lambda ()
     (list
      (vertex
       (pos 0.5 -0.5 -0.5) (uv 0.0 0.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos 0.5 0.5 -0.5) (uv 0.0 1.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos -0.5 0.5 0.5) (uv 1.0 1.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos -0.5 -0.5 0.5) (uv 1.0 0.0) (opgray 1.0) (blocklight) (skylight))))
   (lambda ()
     (list
      (vertex
       (pos 0.5 -0.5  -0.5)  (uv 0.0 0.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos -0.5 -0.5  0.5)  (uv 1.0 0.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos -0.5  0.5  0.5)  (uv 1.0 1.0) (opgray 1.0) (blocklight) (skylight))
      (vertex
       (pos 0.5  0.5  -0.5)  (uv 0.0 1.0) (opgray 1.0) (blocklight) (skylight))))))

(defun renderBlockReed (blockid i j k betlight getskylightz)
  (let* ((faces (make-array 4 :initial-element nil)))
    (let ((lighthere (coerce (funcall betlight 0 0 0) 'float))
	  (skylighthere (coerce (funcall getskylightz 0 0 0) 'float)))
      (dotimes (n 4)
	(let ((newface (funcall (elt xfaces n))))
	  (setf (elt faces n) newface)
	  (dolist (v newface)
	    (setf (elt v 3) (vector (lightfunc lighthere)))
	    (setf (elt v 4) (vector (lightfunc skylighthere)))))))
    faces))

(defun allvec4 (num)
  (vector
   num
   num
   num
   num))

(defun vec4colorize (face colorizer)
  (cunt-verts
   (elt colorizer 0)
   (elt colorizer 1)
   (elt colorizer 2)
   (elt colorizer 3)
   face))

(defun colorize (face colorizer)
  (cunt-verts
   (/ (elt colorizer 0) 256)
   (/ (elt colorizer 1) 256)
   (/ (elt colorizer 2) 256)
   (/ (elt colorizer 3) 256)
   face))

(defun renderblockbyrendertype ())

(defun lightmultiplier (light)
  (let ((ans (lightfunc light)))
    (vector
     ans
     ans
     ans
     1.0)))

(defun lightfunc (light)
  (expt 0.8 (- 15 light)))

(defun lightvert (vert light)
  (let ((anum (lightfunc light)))
    (cunt-verts anum anum anum 1.0 vert)))

(defun vec3getlight (lelight vec3)
  (coerce
   (funcall lelight
	    (elt vec3 0)
	    (elt vec3 1)
	    (elt vec3 2))
   'float))

(defun avg (&rest args)
  (/ (apply (function +) args) (length args)))

;;buns r fun ahun
(defun dayify (num)
  (round (* daytime num)))

(defun insert-at (num vec place)
  (let* ((start (subseq vec 0 place))
	 (end (subseq vec place (length vec))))
    (concatenate 'vector start (vector num) end)))

(defun delete-at (vec place)
  (let* ((start (subseq vec 0 place))
	 (end (subseq vec (1+ place) (length vec))))
    (concatenate 'vector start end)))

(defun lightvert2 (face getlight a b unchange skylit)
  (dolist (v face)
    (let ((vert (elt v 0)))    
      (let ((foo (round (* 2 (elt vert a))))
	    (bar (round (* 2 (elt vert b))))
	    (qux (round (* 2 (elt vert unchange)))))
	(let ((uno (vec3getlight getlight (insert-at  qux (vector foo bar) unchange )))
	      (dos (vec3getlight getlight (insert-at  qux (vector foo 0) unchange )))
	      (tres (vec3getlight getlight (insert-at qux (vector 0 bar) unchange )))
	      (quatro (vec3getlight getlight (insert-at qux (vector 0 0) unchange ))))
	  (let ((foo (round (* 2 (elt vert a))))
		(bar (round (* 2 (elt vert b))))
		(qux (round (* 2 (elt vert unchange)))))
	    (let* ((1dos (vec3getlight skylit (insert-at qux (vector foo 0) unchange )))
		   (1tres (vec3getlight skylit (insert-at qux (vector 0 bar) unchange )))
		   (1quatro (vec3getlight skylit (insert-at qux (vector 0 0) unchange )))
		   (1uno (vec3getlight skylit (insert-at  qux (vector foo bar) unchange ))))
	      (setf (elt v 3) (vector (lightfunc (avg uno dos tres quatro))))
	      (setf (elt v 4) (vector (lightfunc (avg 1uno 1dos 1tres 1quatro))))
	      (progno
	       (let ((anum (lightfunc (avg (max 1uno uno)
					   (max 1dos dos)
					   (max 1tres tres)
					   (max 1quatro quatro)))))
		 (cunt-vert anum anum anum 1.0 (elt v 2)))))))))))

;;0.9 for nether
;;0.8 for overworld
