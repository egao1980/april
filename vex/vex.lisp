;;;; vex.lisp

(in-package #:vex)

;; The idiom object defines a vector language instance with a persistent state.
(defclass idiom ()
  ((name :accessor idiom-name
    	 :initarg :name)
   (state :accessor idiom-state
	  :initarg :state)
   (base-state :accessor idiom-base-state
	       :initarg :state)
   (default-state :accessor idiom-default-state
                  :initarg :state)
   (utilities :accessor idiom-utilities
	      :initarg :utilities)
   (functions :accessor idiom-functions
	      :initform nil
	      :initarg :functions)
   (operators :accessor idiom-operators
	      :initform nil
	      :initarg :operators)
   (operational-glyphs :accessor idiom-opglyphs
		       :initform nil
		       :initarg :operational-glyphs)
   (operator-index :accessor idiom-opindex
		   :initform nil
		   :initarg :operator-index)
   (overloaded-lexicon :accessor idiom-overloaded-lexicon
		       :initform nil
		       :initarg :overloaded-lexicon)))

(defgeneric of-state (idiom property))
(defmethod of-state ((idiom idiom) property)
  (getf (idiom-state idiom) property))

(defgeneric of-utilities (idiom utility))
(defmethod of-utilities ((idiom idiom) utility)
  (getf (idiom-utilities idiom) utility))

(defmacro boolean-op (operation omega &optional alpha)
  "Converts output of a boolean operation from t/nil to 1/0."
  `(lambda ,(if alpha (list omega alpha)
  		(list omega))
     (if (funcall (function ,operation)
  		  ,@(if alpha (list omega alpha)
  			(list omega)))
  	 1 0)))

(defmacro vex-spec (symbol &rest subspecs)
  "Process the specification for a vector language and build functions that generate the code tree."
  (let ((idiom-symbol (intern (format nil "*~a-IDIOM*" (string-upcase symbol))
			      (package-name *package*))))
    (labels ((process-function-definition (is-dyadic is-scalar function-spec)
	       (let ((discrete-function (if (and (listp (first function-spec))
						 (macro-function (caar function-spec))
						 (not (eql 'lambda (caar function-spec))))
					    (macroexpand (append (first function-spec)
								 (cons 'omega (if is-dyadic (list 'alpha)))))
					    (cons 'function function-spec))))
		 (if (not is-scalar)
		     discrete-function
		     `(lambda ,(if is-dyadic (list 'alpha 'omega)
				   (list 'omega))
			,(if is-dyadic `(funcall (of-utilities ,idiom-symbol :apply-scalar-dyadic)
						 ,discrete-function alpha omega)
			     `(funcall (of-utilities ,idiom-symbol :apply-scalar-monadic)
				       ,discrete-function omega)
			     ;; `(if (arrayp omega)
			     ;; 	  (aops:each ,discrete-function omega)
			     ;; 	  (funcall ,discrete-function omega))
			     )))))

	     (assign-discrete-functions (entry)
	       ;; return a list containing the function, or both functions if ambivalent
	       (let ((spec (third entry)))
		 (if (eql 'monadic (first spec))
		     (list (process-function-definition nil (eq :scalar (cadadr spec))
							(last (first (last spec)))))
		     (if (eql 'dyadic (first spec))
			 (list (process-function-definition t (eq :scalar (cadadr spec))
							    (last (first (last spec)))))
			 (list (if (listp (second spec))
				   (process-function-definition nil (or (eq :symmetric-scalar (second spec))
									(eq :scalar (cadadr spec)))
								(last (second spec)))
				   (process-function-definition nil t (if (eq :symmetric-scalar (second spec))
									  (last spec)
									  (list (third spec)))))
			       (if (listp (second spec))
				   (process-function-definition t (eq :scalar (second (third spec)))
								(last (third spec)))
				   (process-function-definition t (or (eq :symmetric-scalar (second spec))
								      (eq :asymmetric-scalar (second spec)))
								(last spec))))))))

	     (process-pairs (table-symbol pairs &optional output)
	       (if pairs
		   (process-pairs table-symbol (rest pairs)
				  (let* ((glyph-char (character (caar pairs)))
					 (accumulator (third output))
					 ;; name of macro to process operation specs
					 (oprocess (getf (rest (assoc (intern "UTILITIES" (package-name *package*))
								      subspecs))
							 :mediate-operation-macro)))
				    (if (and (eql 'op-specs table-symbol))
					(setf (getf accumulator
						    (intern (string-upcase (first (third (first pairs))))
							    "KEYWORD"))
					      (cons 'list (cons glyph-char (rest (getf accumulator
										       (intern (string-upcase
												(first
												 (third (first
													 pairs))))
											       "KEYWORD")))))))
				    (list (cons glyph-char (first output))
					  (append (second output)
						  (cond ((and (eql 'fn-specs table-symbol)
							      (eq :symbolic
								  (intern (string-upcase
									   (first (third (first pairs))))
									  "KEYWORD")))
							 ;; assign symbolic functions as just keywords in the table
							 `((gethash ,glyph-char ,table-symbol)
							   ,(second (third (first pairs)))))
							;; assign functions in hash table
							((eql 'fn-specs table-symbol)
							 `((gethash ,glyph-char ,table-symbol)
							   ,(if (and (listp (second (third (first pairs))))
								     (eq :macro
									 (intern (string-upcase
										  (first (second (third
												  (first pairs)))))
										 "KEYWORD")))
								`(list ,(macroexpand
									 (second (second (third (first pairs))))))
								`(list
								  ,(macroexpand (cons (second oprocess)
										      (list (third (first pairs)))))
								  ,@(assign-discrete-functions (first pairs))))))
							;; assign operators in hash table
							((eql 'op-specs table-symbol)
							 `((gethash ,glyph-char ,table-symbol)
							   ,(if (eq :macro
								    (intern (string-upcase
									     (first (second (third (first pairs)))))
									    "KEYWORD"))
								(macroexpand
								 (second (second (third (first pairs)))))
								`(lambda (meta axes functions operand
									  &optional right-operand)
								   (declare (ignorable meta axes right-operand))
								   `(funcall ,',(second (third (first pairs)))
									     ,(cons 'list axes)
									     ,(if (listp (first functions))
										  (cons 'list
											(mapcar
											 (lambda (f)
											   (if (listp f)
											       (cons 'list (rest f))
											       f))
											 functions))
										  (cons 'list (cdar functions)))
									     ,operand
									     ,@(if right-operand
										   (list right-operand)))))))))
					  accumulator)))
		   output))

	     (process-optests (specs &optional output)
	       (let* ((tests (rest (assoc (intern "TESTS" (package-name *package*))
					  (rest (first specs)))))
		      (props (rest (assoc (intern "HAS" (package-name *package*))
					  (rest (first specs)))))
		      (heading (format nil "[~a] ~a~a"
				       (caar specs)
				       (if (getf props :title)
					   (getf props :title)
					   (if (getf props :titles)
					       (first (getf props :titles))))
				       (if (getf props :titles)
					   (concatenate 'string " / " (second (getf props :titles)))
					   ""))))
		 (labels ((for-tests (tests &optional output)
			    (if tests
				(for-tests (rest tests)
					   (append output (list (cond ((eql 'is (caar tests))
								       `(is (,(intern (string-upcase symbol)
										      (package-name *package*))
									      ,(cadar tests))
									    ,(third (first tests))
									    :test #'equalp))))))
				output)))
		   
		   (if specs
		       (process-optests (rest specs)
					(if (assoc (intern "TESTS" (package-name *package*))
						   (rest (first specs)))
					    (append output (list `(princ ,heading))
						    (for-tests tests)
						    (list `(princ (format nil "~%~%")) nil))
					    output))
		       output))))
	     (process-gentests (specs &optional output)
	       (if specs
		   (let ((this-spec (cdar specs)))
		     (process-gentests (rest specs)
				       (append output `((princ ,(getf this-spec :title))
							(is (,(intern (string-upcase symbol)
								      (package-name *package*))
							      ,@(getf this-spec :in))
							    ,(getf this-spec :ex)
							    :test #'equalp)))))
		   output)))
      (let* ((function-specs (process-pairs 'fn-specs (rest (assoc (intern "FUNCTIONS" (package-name *package*))
								   subspecs))))
	     (operator-specs (process-pairs 'op-specs (rest (assoc (intern "OPERATORS" (package-name *package*))
								   subspecs))))
	     (function-tests (process-optests (rest (assoc (intern "FUNCTIONS" (package-name *package*))
							   subspecs))))
	     (operator-tests (process-optests (rest (assoc (intern "OPERATORS" (package-name *package*))
							   subspecs))))
	     (general-tests (process-gentests (rest (assoc (intern "GENERAL-TESTS" (package-name *package*))
							   subspecs)))))
	`(progn (defvar ,idiom-symbol)
		(let ((fn-specs (make-hash-table))
		      (op-specs (make-hash-table)))
		  (setf ,idiom-symbol
			(make-instance 'idiom
				       :name ,(intern (string-upcase symbol) "KEYWORD")
				       :state ,(cons 'list (rest (assoc (intern "STATE" (package-name *package*))
									subspecs)))
				       :utilities ,(cons 'list
							 (rest (assoc (intern "UTILITIES" (package-name *package*))
								      subspecs))))

			,@(second function-specs)
			,@(second operator-specs)
			(idiom-opglyphs ,idiom-symbol)
			(list ,@(derive-opglyphs
				 (append (first function-specs)
					 (first operator-specs))))
			(idiom-functions ,idiom-symbol)
			fn-specs
			(idiom-operators ,idiom-symbol)
			op-specs
			(idiom-overloaded-lexicon ,idiom-symbol)
			(list ,@(intersection (first function-specs)
					      (first operator-specs)))
			(idiom-opindex ,idiom-symbol)
			(list ,@(third operator-specs)))

		  (defmacro ,(intern (string-upcase symbol)
				     (package-name *package*))
		      (options &optional input-string)
		    ;; this macro is the point of contact between users and the language, used to
		    ;; evaluate expressions and control properties of the language instance
		    (cond ((and options (listp options)
				(eq :test (intern (string-upcase (first options))
						  "KEYWORD")))
			   (cons 'progn ',(append operator-tests function-tests general-tests)))
			  ;; the (test) setting is used to run tests
			  ((and options (listp options)
				(eq :restore-defaults (intern (string-upcase (first options))
							      "KEYWORD")))
			   `(setf (idiom-state ,,idiom-symbol)
				  (copy-alist (idiom-base-state ,,idiom-symbol))))
			  ;; the (set-default) setting is used to restore the instance settings
			  ;; to the defaults from the spec
			  (t (vex-program ,idiom-symbol
					  (if (or input-string (and options (listp options)))
					      (if (eq :set (intern (string-upcase (first options))
								   "KEYWORD"))
						  (rest options)
						  (error "Incorrect option syntax.")))
					  (if (not (listp options))
					      options input-string)))))))))))
  
(defun derive-opglyphs (glyph-list &optional output)
  (if (not glyph-list)
      output (derive-opglyphs (rest glyph-list)
			      (let ((glyph (first glyph-list)))
				(if (characterp glyph)
				    (cons glyph output)
				    (if (stringp glyph)
					(append output (loop for char from 0 to (1- (length glyph))
							  collect (aref glyph char)))))))))

(defun process-reverse (function input &optional output)
  (if input
      (process-reverse function (rest input)
		       (cons (funcall function (first input))
			     output))
      output))

(defun =vex-tree (idiom meta &optional output)
  (labels ((?blank-character () (?satisfies (of-utilities idiom :match-blank-character)))

	   (?token-character () (?satisfies (of-utilities idiom :match-token-character)))

	   (?newline-character () (?satisfies (of-utilities idiom :match-newline-character)))

	   (?but-newline-character ()
	     (?satisfies (lambda (char) (not (funcall (of-utilities idiom :match-newline-character)
						      char)))))

	   (=string (&rest delimiters)
	     (let ((lastc nil)
		   (delimiter nil))
	       (=destructure (_ content _)
		   (=list (?satisfies (lambda (c) (if (member c delimiters)
						      (setq delimiter c))))
			  ;; note: nested quotes must be checked backwards; to determine whether a delimiter
			  ;; indicates the end of the quote, look at previous character to see whether it is a
			  ;; delimiter, then check whether the current character is an escape character #\\
			  (=subseq (%any (?satisfies (lambda (char)
						       (if (or (not lastc)
							       (not (char= char delimiter))
							       (char= lastc #\\))
							   (setq lastc char))))))
			  (?satisfies (lambda (c) (char= c delimiter))))
		 content)))

	   (=vex-axes () ;; handle axes, separated by semicolons
	     (=destructure (element _ rest)
		 (=list (=subseq (%some (?satisfies (lambda (char) (not (char= char #\;))))))
			(=subseq (%any (?satisfies (funcall (lambda () (let ((index 0))
									 (lambda (char)
									   (incf index 1)
									   (and (not (< 1 index))
										(char= char #\;)))))))))
			(=subseq (%any (?satisfies 'characterp))))
	       (if (< 0 (length rest))
		   (cons (parse element (=vex-tree idiom meta))
			 (parse rest (=vex-axes)))
		   (list (parse element (=vex-tree idiom meta))))))

	   (handle-axes (input-string)
	     (cons :axes (let ((axes (mapcar #'first (parse input-string (=vex-axes)))))
			   (list (apply #'vector axes)))))

	   (handle-function (input-string)
	     (let ((formatted-function (funcall (of-utilities idiom :format-function)
						(string-upcase (idiom-name idiom))
						;;(parse input-string (=vex-tree idiom meta))
						(vex-program idiom nil input-string))))
	       (list :fndef (lambda (meta axes omega &optional alpha)
			      (declare (ignorable meta axes))
			      `(funcall ,formatted-function
					,@(if alpha (list (macroexpand alpha)))
					,(macroexpand omega))))))
	   
	   (=vex-closure (boundary-chars &optional transform-by)
	     (let ((balance 1))
	       (=destructure (_ enclosed _)
		   (=list (?eq (aref boundary-chars 0))
			  (=transform (=subseq (%some (?satisfies (lambda (char)
								    (if (char= char (aref boundary-chars 0))
									(incf balance 1))
								    (if (char= char (aref boundary-chars 1))
									(incf balance -1))
								    (< 0 balance)))))
				      (if transform-by transform-by
					  (lambda (string-content)
					    (parse string-content (=vex-tree idiom meta)))))
			  (?eq (aref boundary-chars 1)))
		 enclosed))))

    (setf (fdefinition '=vex-axes-parser) (=vex-axes))

    (=destructure (_ item _ rest _ nextlines)
	(=list (%any (?blank-character))
	       (%or (=transform (=subseq (%some (?token-character)))
				(lambda (string) (funcall (of-utilities idiom :format-value)
							  meta string)))
		    (=vex-closure "()")
		    (=vex-closure "[]" #'handle-axes)
		    (=vex-closure "{}" #'handle-function)
		    (=string #\' #\")
		    (=transform (=subseq (%some (?satisfies (lambda (char)
							      (member char (idiom-opglyphs idiom))))))
				(lambda (string)
				  (let ((char (character string)))
				    `(,(cond ((gethash char (idiom-operators idiom))
					      :op)
					     ((gethash char (idiom-functions idiom))
					      :fn))
				       ,@(if (gethash char (idiom-operators idiom))
					     (list (cond ((member char (getf (idiom-opindex idiom) :right))
							  :right)
							 ((member char (getf (idiom-opindex idiom) :center))
							  :center))))
				       ,char)))))
	       (%any (?blank-character))
	       (=subseq (%any (?but-newline-character)))
	       (%any (?newline-character))
	       (=subseq (%any (?satisfies 'characterp))))
      ;; (if (< 0 (length nextlines))
      ;; 	  (print (list :o1 output item rest)))
      (if (< 0 (length nextlines))
	  (setq output (parse nextlines (=vex-tree idiom meta))))
      ;; (print (list :t output nextlines))
      ;; (if (< 0 (length nextlines))
      ;; 	  (print (list :oo output nextlines)))
      (if (< 0 (length rest))
	  (parse rest (=vex-tree idiom meta (if output (if (< 0 (length nextlines))
							   (cons (list item)
								 output)
							   (cons (cons item (first output))
								 (rest output)))
						(list (list item)))))
	  (cons (cons item (first output))
		(rest output))))))

;;(vex-exp apex::*apex-idiom* (make-hash-table) '(2 (:FN #\+) 2))

(defun vex-exp (idiom meta exp &optional precedent)
  "Convert a Vex parse object into Lisp code, composing objects and invoking the corresponding spec-defined functions accordingly."
  (if (not exp)
      precedent
      (labels ((assemble-value (exp &optional output)
		 (if (or (not exp)
			 (and (listp (first exp))
			      (if (eq :fndef (caar exp))
				  (or output precedent)
				  t)))
		     (values (cond ((and (= 1 (length output))
					 (stringp (first output)))
				    (first output))
				   ((and (listp (first output))
					 (eq :fndef (caar output)))
				    output)
				   ((= 1 (length output))
				    (first output))
				   ((not output) nil)
				   (t (apply #'vector output)))
			     exp)
		     (assemble-value (rest exp)
				     (cons (first exp)
					   output))))
	       (assemble-operation (exp &optional output)
		 (let ((first-out (first output)))
		   (if (or (not exp)
			   (not (listp (first exp))))
		       (values output exp)
		       (assemble-operation (rest exp)
					   (cons (list (caar exp)
						       (cond ((eq :fndef (caar exp))
							      (cadar exp))
							     ((eq :fn (caar exp))
							      (cond ((not output)
								     (gethash (cadar exp)
									      (idiom-functions idiom)))
								    ((eq :fndef (first first-out))
								     (funcall (first (last
										      (gethash
										       (cadar exp)
										       (idiom-functions idiom))))
									      (second first-out)))))
							     ((eq :op (caar exp)))))
					    output))))))
	(if (not precedent)
	    (multiple-value-bind (right-value from-value)
		(assemble-value exp)
	      (vex-exp idiom meta from-value right-value))
	    (multiple-value-bind (operation from-operation)
		(assemble-operation exp)
	      (multiple-value-bind (right-value from-value)
		  (assemble-value from-operation)
		(vex-exp idiom meta from-value (cond ((eq :fndef (caar operation))
						      (if right-value
							  (funcall (cadar operation)
								   meta nil precedent right-value)
							  (funcall (cadar operation)
								   meta nil precedent)))
						     (t (funcall (first (cadar (last operation)))
								 meta nil right-value precedent))))))))))


;; (let ((index 0))
;;   (lambda (glyph)
;; 	 (incf index)
;; 	 (print (list glyph index))
;; 	 (cond ((< 1 index) nil)
;; 	       ((and (gethash glyph (idiom-operators idiom))
;; 		     (member glyph (getf (idiom-opindex idiom) :right)))
;; 		t)
;; 	       ((and (gethash glyph (idiom-operators idiom))
;; 		     (member glyph (getf (idiom-opindex idiom) :center)))
;; 		t)
;; 	       ((gethash glyph (idiom-functions idiom))
;; 		t))))

;; (defun =vex-operation (idiom meta precedent)
;;   "Parse an operation belonging to a Vex expression, returning the operation string and tokens extracted along with the remainder of the expression string."
;;   (let ((at-start? (not precedent)))
;;     (labels ((?blank-character ()
;; 	       (?satisfies (of-utilities idiom :match-blank-character)))

;; 	     (?token-character ()
;; 	       (?satisfies (of-utilities idiom :match-token-character)))

;; 	     (=string (&rest delimiters)
;; 	       (let ((lastc nil)
;; 		     (delimiter nil))
;; 		 (=destructure (_ content)
;; 		     (=list (?satisfies (lambda (c) (if (member c delimiters)
;; 							(setq delimiter c))))
;; 			    ;; note: nested quotes must be checked backwards; to determine whether a delimiter
;; 			    ;; indicates the end of the quote, look at previous character to see whether it is a
;; 			    ;; delimiter, then check whether the current character is an escape character #\\
;; 			    (=subseq (%any (?satisfies (lambda (c)
;; 							 ;; TODO: this causes a problem when a quote mark ' or "
;; 							 ;; is immediately preceded by a slash: 2\'.'
;; 							 (if (or (not lastc)
;; 								 (not (char= lastc delimiter))
;; 								 (char= c #\\))
;; 							     (setq lastc c)))))))
;; 		   (format nil "~a~a" delimiter content))))

;; 	     (=vex-opglyphs (&optional ops)
;; 	       (flet ((glyph-finder (glyph)
;; 			(cond ((and (not (getf ops :op))
;; 				    (gethash glyph (idiom-operators idiom)))
;; 			       (if (and (not ops)
;; 					(not (getf ops :fn))
;; 					(member glyph (getf (idiom-opindex idiom) :right)))
;; 				   (setf (getf ops :op) glyph)
;; 				   (if (and (getf ops :fn)
;; 					    (member glyph (getf (idiom-opindex idiom) :center)))
;; 				       (setf (getf ops :op) glyph))))
;; 			      ((gethash glyph (idiom-functions idiom))
;; 			       (if (not (getf ops :fn))
;; 				   (setf (getf ops :fn) glyph)
;; 				   (if (and (getf ops :op)
;; 					    (member (getf ops :op)
;; 						    (getf (idiom-opindex idiom) :center))
;; 					    (not (getf ops :afn)))
;; 				       (setf (getf ops :afn) glyph))))
;; 			      (t nil))))
;; 		 (=destructure (_ glyph-group)
;; 		     (=list (%any (?blank-character))
;; 			    (=subseq (%any (?satisfies #'glyph-finder))))
;; 		   (declare (ignore glyph-group))
;; 		   ;; if only an operator was found, check whether the glyph is a member of the
;; 		   ;; overloaded lexicon. If so, it will be reassigned as a function glyph, if not an
;; 		   ;; error will occur
;; 		   (if (and (getf ops :op)
;; 			    (not (getf ops :fn)))
;; 		       (if (member (getf ops :op)
;; 				   (idiom-overloaded-lexicon idiom))
;; 			   (setf (getf ops :fn) (getf ops :op)
;; 				 (getf ops :op) nil)))
;; 		   ops)))

;; 	     (=vex-glyphs (&optional ops)
;; 	       (let ((index 0))
;; 		 (print (list :oo ops))
;; 		 (flet ((glyph-finder (glyph)
;; 			  (incf index 1)
;; 			  (print (list :gl glyph))
;; 			  (cond ((< 1 index) nil)
;; 				((and (not (getf ops :op))
;; 				      (gethash glyph (idiom-operators idiom)))
;; 				 (if (and (not ops)
;; 					  (not (getf ops :fn))
;; 					  (member glyph (getf (idiom-opindex idiom) :right)))
;; 				     (setf (getf ops :op) glyph)
;; 				     (if (and (getf ops :fn)
;; 					      (member glyph (getf (idiom-opindex idiom) :center)))
;; 					 (setf (getf ops :op) glyph))))
;; 				((gethash glyph (idiom-functions idiom))
;; 				 (if (not (getf ops :fn))
;; 				     (setf (getf ops :fn) glyph)
;; 				     (if (and (getf ops :op)
;; 					      (member (getf ops :op)
;; 						      (getf (idiom-opindex idiom) :center))
;; 					      (not (getf ops :afn)))
;; 					 (setf (getf ops :afn) glyph))))
;; 				(t nil))))
;; 		   (print 909)
;; 		   (=destructure (_ glyph-group)
;; 		       (=list (%any (?blank-character))
;; 			      (=subseq (%some (?satisfies #'glyph-finder))))
;; 		     ;;(declare (ignore glyph-group))
;; 		     (print (list :gp glyph-group))
;; 		     ;; if only an operator was found, check whether the glyph is a member of the
;; 		     ;; overloaded lexicon. If so, it will be reassigned as a function glyph, if not an
;; 		     ;; error will occur
;; 		     (if (and (getf ops :op)
;; 			      (not (getf ops :fn)))
;; 			 (if (member (getf ops :op)
;; 				     (idiom-overloaded-lexicon idiom))
;; 			     (setf (getf ops :fn) (getf ops :op)
;; 				   (getf ops :op) nil)))
;; 		     ops))))

;; 	     (=vex-operations (&optional ops) ;;recursive parser for operations - functions and/or operators
;; 	       (print (list :aa))
;; 	       (=destructure (_ op rest)
;; 		   (=list (%and (?blank-character))
;; 			  (%or (=list (%maybe (=vex-closure "[]" #'handle-axes))
;; 				      (%some (=vex-glyphs ops)))
;; 			       (=vex-closure "{}" #'handle-function)
;; 			       (=subseq (%some (?token-character))))
;; 			  (=subseq (%any (?satisfies 'characterp))))
;; 		 (print (list :rr op rest))
;; 		 (if rest (list op rest))))
	     
;; 	     (=vex-tokens (&optional first-token?) ;; recursive parser for tokens and closures
;; 	       (=destructure (_ axis _ token _ last)
;; 		   (=list (%any (?blank-character))
;; 			  (%maybe (=vex-closure "[]" #'handle-axes))
;; 			  (%any (?blank-character))
;; 			  (if (and first-token? at-start?)
;; 			      ;; only process a function as a value if it's the first token in the expression
;; 			      (%or (=vex-closure "{}" #'handle-function-as-data)
;; 				   (=subseq (%some (?token-character)))
;; 				   (=string #\' #\")
;; 				   (=vex-closure "()"))
;; 			      (%or (=subseq (%some (?token-character)))
;; 				   (=string #\' #\") (=vex-closure "()")))
;; 			  (%any (?blank-character))
;; 			  (=subseq (%any (?satisfies 'characterp))))
;; 		 (let ((token (if (not axis)
;; 				  token (list :axis axis token)))
;; 		       (next (parse last (=vex-tokens))))
;; 		   (if (or (not (stringp token))
;; 			   (not (member (funcall (of-utilities idiom :format-value)
;; 						 meta (reverse token))
;; 					(gethash :functions meta))))
;; 		       (if next (list (cons token (first next))
;; 				      (second next))
;; 			   (list (list token) last))))))

;; 	     (=vex-closure (boundary-chars &optional transform-by)
;; 	       (let ((balance 1))
;; 		 (=destructure (_ enclosed _)
;; 		     (=list (?eq (aref boundary-chars 1))
;; 			    (=transform (=subseq (%some (?satisfies (lambda (char)
;; 								      (if (char= char (aref boundary-chars 1))
;; 									  (incf balance 1))
;; 								      (if (char= char (aref boundary-chars 0))
;; 									  (incf balance -1))
;; 								      (< 0 balance)))))
;; 					(if transform-by transform-by
;; 					    (lambda (string-content)
;; 					      (vex-expression idiom meta string-content))))
;; 			    (?eq (aref boundary-chars 0)))
;; 		   enclosed)))

;; 	     (=vex-axes () ;; handle axes, separated by semicolons
;; 	       (=destructure (element _ next last)
;; 		   (=list (=subseq (%some (?satisfies (lambda (c) (not (char= c #\;))))))
;; 			  (?eq #\;)
;; 			  (%maybe '=vex-axes-parser)
;; 			  (=subseq (%any (?satisfies (lambda (c) (not (char= c #\;)))))))
;; 		 (if next (cons element next)
;; 		     (list element last))))

;; 	     (handle-axes (input-string)
;; 	       (let ((axes (parse input-string (=vex-axes))))
;; 		 ;; reverse the order of axes, since we're parsing backwards
;; 		 (process-reverse (lambda (string-content) (vex-expression idiom meta string-content))
;; 				  (if axes axes (list input-string)))))
	     
;; 	     (handle-function (input-string)
;; 	       (let ((formatted-function (funcall (of-utilities idiom :format-function)
;; 						  (string-upcase (idiom-name idiom))
;; 						  (vex-expression idiom meta input-string))))
;; 		 (lambda (meta axes omega &optional alpha)
;; 		   (declare (ignorable meta axes))
;; 		   `(funcall ,formatted-function
;; 			     ,@(if alpha (list (macroexpand alpha)))
;; 			     ,(macroexpand omega)))))
	     
;; 	     (handle-function-as-data (input-string)
;; 	       (funcall (of-utilities idiom :format-function)
;; 			(string-upcase (idiom-name idiom))
;; 			(vex-expression idiom meta input-string))))
      
;;       (setf (fdefinition '=vex-tokens-parser) (=vex-tokens)
;; 	    (fdefinition '=vex-axes-parser) (=vex-axes)
;; 	    (fdefinition '=vex-ops-parser) (=vex-operations))
      
;;       (=destructure (_ hd tl last)
;; 	  (if at-start? ;; handle the initial value in the expression at the start
;; 	      (=list (%any (?blank-character))
;; 		     (%maybe (=vex-tokens t))
;; 		     (=subseq (%any (?satisfies 'characterp)))
;; 		     (=subseq (%any (?satisfies 'characterp))))
;; 	      ;; then handle each operation (function and sometimes operator) and the following tokens
;; 	      (=list (%any (?blank-character))
;; 		     ;; (=list (%maybe (=vex-closure "[]" #'handle-axes))
;; 		     ;; 	  (%or (=vex-closure "{}" #'handle-function)
;; 		     ;; 	       (=subseq (%some (?token-character)))
;; 		     ;; 	       (=vex-opglyphs)))
;; 		     (%maybe (=vex-operations))
;; 		     (%maybe (=vex-tokens))
;; 		     (=subseq (%any (?satisfies 'characterp)))))
;; 	(if (and (not at-start?)
;; 		 (stringp (second hd)))
;; 	    (let ((function-string (second hd)))
;; 	      (setq hd (list (first hd)
;; 			     (function (lambda (meta axes omega &optional alpha)
;; 			       (declare (ignorable meta axes))
;; 			       `(funcall ,(funcall (of-utilities idiom :format-value)
;; 						   meta (reverse function-string))
;; 					 ,@(if alpha (list (macroexpand alpha)))
;; 					 ,(macroexpand omega))))))))
;; 	(if at-start? (setq tl hd hd nil))
;; 	(print (list :tt hd tl last precedent))
;; 	(if (eq :f-compositional precedent)
;; 	    (error "Cut."))
;; 	(list hd (if tl
;; 		     (list (process-reverse (lambda (value) (cond ((stringp value)
;; 								   (funcall (of-utilities idiom :format-value)
;; 									    meta (reverse value)))
;; 								  ((and (listp value)
;; 									(eq :axis (first value)))
;; 								   `(apply #'aref
;; 									   (cons ,(if (stringp (third value))
;; 										      (funcall
;; 										       (of-utilities idiom
;; 												     :format-value)
;; 										       meta (reverse (third value)))
;; 										      (third value))
;; 										 (mapcar (lambda (i)
;; 											   (1- (aref i 0)))
;; 											 (list ,@(second value))))))
;; 								  (t value)))
;; 					    (first tl))
;; 			   (second tl))
;; 		     (list nil last)))))))

;; (defun vex-expression (idiom meta string &optional precedent)
;;   "Convert an expression into Lisp code, parsing the text and invoking the corresponding spec-defined functions accordingly."
;;   (if (= 0 (length string))
;;       precedent
;;       (let* ((next-operation (parse string (=vex-operation idiom meta precedent)))
;; 	     (operation (cadar next-operation))
;; 	     (operation-axes (caar next-operation))
;; 	     (value-results (second next-operation))
;; 	     (operator (if (not (or (functionp operation)
;; 				    (eql 'lambda (first operation))))
;; 			   (gethash (getf operation :op)
;; 				    (idiom-operators idiom))))
;; 	     (function (if (or (functionp operation)
;; 			       (eql 'lambda (first operation)))
;; 			   (list operation)
;; 			   (gethash (getf operation :fn)
;; 				    (idiom-functions idiom))))
;; 	     (alpha-function (if (not (or (functionp operation)
;; 					  (eql 'lambda (first operation))))
;; 				 (gethash (getf operation :afn)
;; 					  (idiom-functions idiom)))))
;; 	(if (and (not operation)
;; 		 (not (first value-results)))
;; 	    ;; if there's still a string, pass it through again with :f-compositional as precedent,
;; 	    ;; indicating that this expression probabably consists of functions being composed by an operator.
;; 	    (vex-expression idiom meta string :f-compositional)
;; 	    (vex-expression idiom meta (second value-results)
;; 			    (apply (cond (operator operator)
;; 					 (function (first function))
;; 					 (t (lambda (&rest items) (third items))))
;; 				   (append (list meta operation-axes)
;; 					   (if operator
;; 					       (list (cons function (if alpha-function (list alpha-function)))))
;; 					   (if (first value-results)
;; 					       (list (funcall (of-utilities idiom :format-object)
;; 							      (first value-results))))
;; 					   (if precedent (list precedent)))))))))

(defun vex-program (idiom options &optional string meta)
  "Compile a set of expressions, optionally drawing external variables into the program and setting configuration parameters for the system."
  (let ((meta (if meta meta (make-hash-table :test #'eq)))
	(state (rest (assoc :state options)))
	(state-persistent (rest (assoc :state-persistent options))))
    (labels ((assign-from (source dest)
	       (if source
		   (progn (setf (getf dest (first source))
				(second source))
			  (assign-from (cddr source)
				       dest))
		   dest)))

      (setf (gethash :functions meta) nil
	    (gethash :variables meta) (make-hash-table :test #'eq)
	    (idiom-state idiom) (idiom-base-state idiom))

      (if state (setf (idiom-state idiom)
		      (assign-from state (copy-alist (idiom-base-state idiom)))))

      (if state-persistent (setf (idiom-state idiom)
      				 (assign-from state-persistent (idiom-base-state idiom))))

      (if string
	  (let* ((input-vars (getf (idiom-state idiom) :in))
		 (output-vars (getf (idiom-state idiom) :out))
		 (compiled-expressions (loop for exp in (parse (funcall (of-utilities idiom :prep-code-string)
									string)
							       (=vex-tree idiom meta))
					  collect (vex-exp idiom meta exp)))
		 (vars-declared (loop for key being the hash-keys of (gethash :variables meta)
				   when (not (member (string (gethash key (gethash :variables meta)))
						     (mapcar #'first input-vars)))
				   collect (list (gethash key (gethash :variables meta))
						 :undefined))))

	    (if input-vars
		(loop for var-entry in input-vars
		   ;; TODO: move these APL-specific checks into spec
		   do (if (gethash (intern (lisp->camel-case (first var-entry))
					   "KEYWORD")
				   (gethash :variables meta))
			  (rplacd (assoc (gethash (intern (lisp->camel-case (first var-entry))
							  "KEYWORD")
						  (gethash :variables meta))
					 vars-declared)
				  (list (second var-entry)))
			  (setq vars-declared (append vars-declared
						      (list (list (setf (gethash (intern (lisp->camel-case
											  (first var-entry))
											 "KEYWORD")
										 (gethash :variables meta))
									(gensym))
								  (second var-entry))))))))

	    (let ((code `(,@(if vars-declared
				`(let ,vars-declared)
				'(progn))
			    ,@compiled-expressions
			    ,@(if output-vars
				  (list (cons 'values (mapcar (lambda (return-var)
								(gethash (intern (lisp->camel-case return-var)
										 "KEYWORD")
									 (gethash :variables meta)))
							      output-vars)))))))

	      (if (assoc :compile-only options)
		  `(quote ,code)
		  code)))))))
