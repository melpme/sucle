(defpackage #:deflazy
  (:use #:cl #:utility)
  (:export
   #:getfnc
   #:deflazy
   #:refresh
   #:flush-refreshes))

(in-package :deflazy)

(struct-to-clos:struct->class
 (defstruct env
   (cells-nodes
    (make-hash-table :test 'eq))
   (names-nicknames nil)
   (tree nil)))

(defparameter *env* (make-env))

(defun set-env-var (name value env)
  (let ((hash (env-cells-nodes env)))
    (setf (gethash name hash)
	  value)))
(defun get-env-var (name env)
  (let ((hash (env-cells-nodes env)))
    (gethash name hash)))

(defun nicknamify (name env)
  ;;FIXME::name doesn't do anything?
  ;;turn global namespace names into local nicknames
  ;;FIXME::misnomer
  ;;(format t "~%env-tree ~a" (env-tree env))
  (let ((alist (env-names-nicknames env)))
    ;;(print (list name alist))
    (let ((thing (assoc name alist)))
      (if thing
	  (name-pair-nick thing)
	  name))))

(defun next-env (name env)
  (let* ((tree (env-tree env))
	 (subtree (find-nick-subtree name tree))
	 (maybe-env (tree-subtrees subtree)))
    ;;(print (list tree name subtree))
    (if (env-p maybe-env)
	maybe-env
	(create-env subtree
		    (remove-if 'symbolp (collect-tree-names subtree))
		    #+nil
		    (nickname-foo (tree-name subtree)
				  (env-names-nicknames env))
		    (env-cells-nodes env)))))

(defun create-env (&optional (tree *tree*) (old-nicknames (list (nickname-foo (tree-name tree) nil)))
		     (cells-nodes (make-hash-table :test 'eq)))
  (make-env
   :cells-nodes cells-nodes
   :tree tree
   :names-nicknames old-nicknames))

(eval-always
  ;;Holds the global symbol to function bindings
  (defvar *function-stuff* (make-hash-table :test 'eq)))

(defparameter *name-stack* nil)

(eval-always
  (defun separate-bindings (deps)
    (values (mapcar (lambda (x)
		      (etypecase x
			(symbol x)
			(list (first x))))
		    deps)
	    (mapcar (lambda (x)
		      (etypecase x
			(symbol x)
			(list (second x))))
		    deps))))

(defun get-node (global-name &key (env *env*))
  (let ((local-name (nicknamify global-name env)))
    (multiple-value-bind (value existsp)
	(get-env-var local-name env)
      (if existsp
	  value
	  (multiple-value-bind (fun existsp)
	      (gethash global-name *function-stuff*)
	    (if existsp
		(let* (;;FIXME::the cons cell for representing the name/nickname pair is undocumented
		       ;;(next-stack-value (make-name-pair global-name local-name))
		       (new-value
			(let (#+nil
			      (*name-stack*
			       (cons next-stack-value *name-stack*))
			      (*env* env))
			  (funcall (car fun)))))
		  (set-env-var local-name
			       new-value
			       env)
		  new-value)
		(error "no deflazy node defined named ~s" global-name)))))))

;;deflazy can take multiple forms:
;;(deflazy name ((nick name) other))
;;(deflazy (name :unchanged-if eql) ())
(defmacro deflazy (name (&rest deps) &body gen-forms)
  (let ((unchanged-if nil)) ;;FIXME::backwards compatibility deflazy hack
    (etypecase name
      (symbol)
      (list (destructuring-bind (unwrapped-name
				 &key ((:unchanged-if nick) nil))
		name
	      (setf name unwrapped-name)
	      (setf unchanged-if nick))))
    (multiple-value-bind (lambda-args names)
	(separate-bindings deps)
      (let ((let-args (mapcar (lambda (lambda-arg name)
				`(,lambda-arg (getfnc ',name)))
			      lambda-args
			      names))
	    (dummy-redefinition-node (symbolicate2 `("%*%" ,name "-deflazy-redefine%*%")))
	    (scrambled-name (symbolicate2 `("%*%deflazy-function-" ,name "-deflazy-function%*%")))
	    (scrambled-name2 (symbolicate2
			      `("%*%deflazy-cell-function-" ,name "-deflazy-cell-function%*%")))
	    (self (gensym)))
	`(progn
	   (setf (gethash ',name *function-stuff*)
		 (cons ',scrambled-name ',dummy-redefinition-node))
	   (defparameter ,dummy-redefinition-node
	     (if (boundp ',dummy-redefinition-node)
		 (let ((old-value (symbol-value ',dummy-redefinition-node)))
		   (%%refresh old-value)
		   old-value)
		 (make-instance 'node :value (cells:c? "nothing"))))
	   (defun ,scrambled-name2 (,self)
	     (let ,let-args
	       (declare (ignorable ,@lambda-args))
	       (injected-fun)
	       (node-update-p ,self)
	       (node-update-p ,dummy-redefinition-node)
	       (locally
		   ,@gen-forms)))
	   (defun ,scrambled-name ()
	     (let (;;(captured-name-stack *name-stack*)
		   (captured-env *env*))
	       (make-instance
		',(ecase unchanged-if
		    ((nil) 'node)
		    (eql 'node-eql)
		    (= 'node-=))
		:value 
		(cells:c?_
		  (let ((*env* (next-env ',name captured-env))
			;;(*name-stack* captured-name-stack)
			)
		    (,scrambled-name2 cells:self)))))))))))

(defun injected-fun ()
  ;;(print *name-stack*)
  )

(defparameter *refresh* (make-hash-table :test 'eq))
(defparameter *refresh-lock* (bordeaux-threads:make-recursive-lock "refresh"))
(defun refresh (name main-thread &key (env *env*))
  (if main-thread
      (%refresh name :env env)
      (bordeaux-threads:with-recursive-lock-held (*refresh-lock*)
	(setf (gethash name *refresh*) t))))
(defun flush-refreshes (&key (env *env*))
  (bordeaux-threads:with-recursive-lock-held (*refresh-lock*)
    (let ((length (hash-table-count *refresh*)))
      (unless (zerop length)
	(dohash (name value) *refresh*
		(declare (ignore value))
		(%refresh name :env env))
	(clrhash *refresh*)))))

(defgeneric cleanup-node-value (object))
(defmethod cleanup-node-value ((object t))
  (declare (ignorable object)))

#+nil ;;attempt to make it so when code is reevaluated, all cells defined within get updated
(defmacro runtime-once-only (&body body)
  (let ((cell (gensym)))
    `(let ((,cell
	    (load-time-value (cons nil nil))))
       (unless (car ,cell)
	 (setf (car ,cell) t)
	 (locally ,@body)))))

;;TODO? have an automatic system for different comparison operators?
(cells:defmodel node ()
  ((update-p :cell t
	     :initform (cells:c-in 0)
	     :accessor node-update-p)
   (value :initarg :value
	  :unchanged-if (constantly nil)
	  :accessor node-value
	  :cell t)))
(cells:defmodel node-eql ()
  ((update-p :cell t
	     :initform (cells:c-in 0)
	     :accessor node-update-p)
   (value :initarg :value
	  ;;:unchanged-if #'eql
	  :accessor node-value
	  :cell t)))
(cells:defmodel node-= ()
  ((update-p :cell t
	     :initform (cells:c-in 0)
	     :accessor node-update-p)
   (value :initarg :value
	  :unchanged-if #'=
	  :accessor node-value
	  :cell t)))

(defun getfnc (name &key (env *env*))
  (%getfnc (get-node name :env env)))
(defun %getfnc (node)
  (node-update-p node)
  (node-value node))

#+nil
(defun (setf %getfnc) (new node)
  (setf (node-value node) new))

(cells:defobserver value (self new-value old-value old-value-boundp)
  (when old-value-boundp
    ;;(print old-value)
    (cleanup-node-value old-value)))

(defun %refresh (name &key (env *env*))
  (%%refresh (get-node name :env env)))
(defun %%refresh (node)
  (incf (node-update-p node)))

;;test cases for deflazy
(deflazy (bar :unchanged-if eql) () 122242344)
(deflazy foobar (bar)
  (+ 9 (print bar)))

(deflazy noop () "wat")

;;FIXME::does not actually work, or does it?
;;Does not clean up cells, TODO?
(defun destroy-all ()
  (cells::cells-reset)
  (setf *env* (make-env))
  (dohash (name value) *function-stuff*
	  (declare (ignorable name))
	  (makunbound (cdr value))))

;;TODO::have multiple instances of deflazy things with programmatically controlled dependencies

;;tree -> ([name|(name nick)] (&optional *env*) &rest trees)
(defparameter *tree*
  #+nil
  '((test2 . top)
    ((test0 . test0)
     ((quux . quux-0)))
    ((test1 . test1)
     ((quux . quux-1))))
  #+nil
  '(dummy-root ()
    (test2 ()
     (test0 ()
      (quux ()))
     ((test1) ()
      (foobar ()))))
  '(()
    ((test2 . top)
     ((test0 . test0)
      ((quux . quux-0)))
     ((test1 . test100)
      ((quux . quux-1))))))
(defun tree-subtrees (tree)
  (cdr tree))
(defun tree-name (tree)
  (car tree))
(defun make-name-pair (name nick)
  (cons name nick))
(defun name-pair-name (name-pair)
  (car name-pair))
(defun name-pair-nick (name-pair)
  (cdr name-pair))
(deftype name-pair () '(cons symbol symbol))
(defun nick (name-pair-or-sym)
  (etypecase name-pair-or-sym
    (symbol name-pair-or-sym)
    (name-pair (name-pair-nick name-pair-or-sym))))

(defun find-nick-subtree (nick &optional (tree *tree*))
  ;;(format t "~%nick-subtree ~a ~a" list nick)
  (find-if (lambda (x)
	     (let ((name (tree-name x)))
	       (etypecase name
		 (symbol (eq nick name))
		 (list (eq nick (name-pair-name name))))))
	   (tree-subtrees tree)))
(defun subtree-names (&optional (tree *tree*))
  ;;(format t "~%nick-subtree ~a ~a" list nick)
  (mapcar #'tree-name
	  (tree-subtrees tree)))
(defun collect-tree-names (&optional (tree *tree*))
  (let ((pairs ()))
    (labels ((walk (tree)
	       (push (tree-name tree) pairs)
	       (dolist (subtree (tree-subtrees tree))
		 (walk subtree))))
      (walk tree))
    pairs))

(defun nickname-foo (name-pair value)
  (if (typep name-pair 'name-pair)
      (cons name-pair value)
      value))
(deflazy quux () 34)
(deflazy test0 (quux) (+ quux 2))
(deflazy test1 (quux) (+ quux 20))
(deflazy test2 (test0 test1) (+ test0 test1))

;;(defparameter *tree*)
(defun reset-enanv ()
  (defparameter *enanv* (create-env *tree*)))
(defun test34 (&optional (env (create-env *tree*)))
  (getfnc 'test2 :env env))

(defun test23 ()
  (reset-enanv)
  (test34 *enanv*))
