;;; -*- Mode:Lisp; Syntax:ANSI-Common-Lisp; Coding:utf-8; Package:April -*-
;;;; library.lisp

(in-package #:april)

"This file contains the functions in April's 'standard library' that aren't provided by the aplesque package, mostly functions that are specific to the APL language and not generally applicable to array processing."

(defun without (omega alpha)
  "Remove elements in omega from alpha. Used to implement dyadic [~ without]."
  (flet ((compare (o a)
	   (funcall (if (and (characterp a) (characterp o))
			#'char= (if (and (numberp a) (numberp o))
				    #'= (lambda (a o) (declare (ignore a o)))))
		    o a)))
    (let ((included)
	  (omega-vector (if (or (vectorp omega)	(not (arrayp omega)))
			    (disclose omega)
			    (make-array (array-total-size omega)
					:displaced-to omega :element-type (element-type omega)))))
      (loop :for element :across alpha
	 :do (let ((include t))
	       (if (vectorp omega-vector)
		   (loop :for ex :across omega-vector
		      :do (if (compare ex element) (setq include nil)))
		   (if (compare omega-vector element) (setq include nil)))
	       (if include (setq included (cons element included)))))
      (make-array (list (length included)) :element-type (element-type alpha)
		  :initial-contents (reverse included)))))

(defun scalar-compare (comparison-tolerance)
  "Compare two scalar values as appropriate for APL."
  (lambda (omega alpha)
    (funcall (if (and (characterp alpha) (characterp omega))
		 #'char= (if (and (numberp alpha) (numberp omega))
			     (if (not (or (floatp alpha) (floatp omega)))
				 #'= (lambda (a o) (> comparison-tolerance (abs (- a o)))))
			     (lambda (a o) (declare (ignore a o)))))
	     omega alpha)))

(defun compare-by (symbol comparison-tolerance)
  (lambda (omega alpha)
    (funcall (if (and (numberp alpha) (numberp omega))
		 (if (not (or (floatp alpha) (floatp omega)))
		     (symbol-function symbol) (lambda (a o) (and (< comparison-tolerance (abs (- a o)))
								 (funcall (symbol-function symbol) a o)))))
	     omega alpha)))

(defun count-to (index index-origin)
  "Implementation of APL's ⍳ function."
  (let ((index (disclose index)))
    (if (integerp index)
	(if (= 0 index) (vector)
	    (let ((output (make-array index :element-type (list 'integer 0 index))))
	      (xdotimes output (i index) (setf (aref output i) (+ i index-origin)))
	      output))
	(if (vectorp index)
	    (let ((output (make-array (array-to-list index))))
	      (across output (lambda (elem coords)
			       (declare (ignore elem))
			       (setf (apply #'aref output coords)
				     (make-array (length index)
						 :element-type
						 (list 'integer 0 (+ index-origin (reduce #'max coords)))
						 :initial-contents
						 (if (= 0 index-origin)
						     coords (loop :for c :in coords
							       :collect (+ c index-origin)))))))
	      output)
	    (error "The argument to [⍳ index] must be an integer, i.e. ⍳9, or a vector, i.e. ⍳2 3.")))))

(defun inverse-count-to (vector index-origin)
  "The [⍳ index] function inverted; it returns the length of a sequential integer array starting from the index origin or else throws an error."
  (if (not (vectorp vector))
      (error "Inverse [⍳ index] can only be invoked on a vector, at least for now.")
      (if (loop :for e :across vector :for i :from index-origin :always (= e i))
	  (length vector) (error "The argument to inverse [⍳ index] is not an index vector."))))

(defun shape (omega)
  "Get the shape of an array, implementing monadic [⍴ shape]."
  (if (or (not (arrayp omega))
	  (= 0 (rank omega)))
      #() (if (and (listp (type-of omega))
		   (eql 'simple-array (first (type-of omega)))
		   (eq t (second (type-of omega)))
		   (eq nil (third (type-of omega))))
	      0 (if (vectorp omega)
		    (make-array 1 :element-type (list 'integer 0 (length omega))
				:initial-contents (list (length omega)))
		    (let* ((omega-dims (dims omega))
			   (max-dim (reduce #'max omega-dims)))
		      (make-array (length omega-dims)
				  :initial-contents omega-dims :element-type (list 'integer 0 max-dim)))))))

(defun reshape-array (metadata-symbol)
  "Wrap (aplesque:reshape-to-fit) so that dyadic [⍴ shape] can be implemented with the use of empty-array prototypes."
  (lambda (omega alpha)
    (let ((output (reshape-to-fit omega (if (arrayp alpha) (array-to-list alpha)
					    (list alpha))
				  :populator (build-populator metadata-symbol omega))))
      (if (and (= 0 (size output)) (arrayp (row-major-aref omega 0)))
	  (set-workspace-item-meta metadata-symbol output
				   :eaprototype
				   (make-prototype-of (funcall (if (= 0 (rank omega)) #'identity #'aref)
							       (row-major-aref omega 0)))))
      output)))

(defun at-index (omega alpha axes index-origin &optional to-set)
  "Find the value(s) at the given index or indices in an array. Used to implement [⌷ index]."
  (if (not (arrayp omega))
      (if (and (numberp alpha)
	       (= index-origin alpha))
	  omega (error "Invalid index."))
      (choose omega (let ((coords (funcall (if (arrayp alpha) #'array-to-list #'list)
					   (apply-scalar #'- alpha index-origin)))
			  ;; the inefficient array-to-list is used here in case of nested
			  ;; alpha arguments like (⊂1 2 3)⌷...
			  (axis (if axes (if (vectorp (first axes))
					     (loop :for item :across (first axes)
						:collect (- item index-origin))
					     (if (integerp (first axes))
						 (list (- (first axes) index-origin)))))))
		      (if (not axis)
			  ;; pad coordinates with nil elements in the case of an elided reference
			  (append coords (loop :for i :below (- (rank omega) (length coords)) :collect nil))
			  (loop :for dim :below (rank omega)
			     :collect (if (member dim axis) (first coords))
			     :when (member dim axis) :do (setq coords (rest coords)))))
	      :set to-set)))

(defun find-depth (omega)
  "Find the depth of an array, wrapping (aplesque:array-depth). Used to implement [≡ depth]."
  (if (not (arrayp omega))
      0 (array-depth omega)))

(defun find-first-dimension (omega)
  "Find the first dimension of an array. Used to implement [≢ first dimension]."
  (if (= 0 (rank omega))
      1 (first (dims omega))))

(defun membership (omega alpha)
  "Determine if elements of alpha are present in omega. Used to implement dyadic [∊ membership]."
  (flet ((compare (item1 item2)
	   (if (and (characterp item1) (characterp item2))
	       (char= item1 item2)
	       (if (and (numberp item1) (numberp item2))
		   (= item1 item2)
		   (if (and (arrayp item1) (arrayp item2))
		       (array-compare item1 item2))))))
    (if (not (arrayp alpha))
	(if (not (arrayp omega))
	    (if (compare omega alpha) 1 0)
	    (if (not (loop :for item :across omega :never (compare item alpha)))
		1 0))
	(let* ((output (make-array (dims alpha) :element-type 'bit :initial-element 0))
	       (omega (enclose-atom omega))
	       (to-search (if (vectorp omega)
			      omega (make-array (array-total-size omega)
						:displaced-to omega :element-type (element-type omega)))))
	  ;; TODO: this could be faster with use of a hash table and other additions
	  (xdotimes output (index (array-total-size output))
	    (let ((found))
	      (loop :for item :across to-search :while (not found)
		 :do (setq found (compare item (row-major-aref alpha index))))
	      (if found (setf (row-major-aref output index) 1))))
	  output))))
  
(defun where-equal-to-one (omega index-origin)
  "Return a vector of coordinates from an array where the value is equal to one. Used to implement [⍸ where]."
  (let* ((indices) (match-count 0)
	 (orank (rank omega)))
    (if (= 0 orank)
	(if (= 1 omega) 1 0)
	(progn (across omega (lambda (index coords)
			       ;; (declare (dynamic-extent index coords))
			       (if (= 1 index)
				   (let* ((max-coord 0)
					  (coords (mapcar (lambda (i)
							    (setq max-coord
								  (max max-coord (+ i index-origin)))
							    (+ i index-origin))
							  coords)))
				     (incf match-count)
				     (setq indices (cons (if (< 1 orank)
							     (make-array
							      orank :element-type (list 'integer 0 max-coord)
							      :initial-contents coords)
							     (first coords))
							 indices))))))
	       (if (not indices)
		   0 (make-array match-count :element-type (if (< 1 orank)
							       t (list 'integer 0 (reduce #'max indices)))
				 :initial-contents (reverse indices)))))))

(defun tabulate (omega)
  "Return a two-dimensional array of values from an array, promoting or demoting the array if it is of a rank other than two. Used to implement [⍪ table]."
  (if (not (arrayp omega))
      omega (if (vectorp omega)
		(let ((output (make-array (list (length omega) 1) :element-type (element-type omega))))
		  (loop :for i :below (length omega) :do (setf (row-major-aref output i) (aref omega i)))
		  output)
		(let ((o-dims (dims omega)))
		  (make-array (list (first o-dims) (reduce #'* (rest o-dims)))
			      :element-type (element-type omega)
			      :displaced-to (copy-nested-array omega))))))

(defun ravel-array (index-origin)
  "Wrapper for aplesque [,ravel] function incorporating index origin from current workspace."
  (lambda (omega &optional axes)
    (ravel index-origin omega axes)))

(defun catenate-arrays (index-origin)
  "Wrapper for [, catenate] incorporating (aplesque:catenate) and (aplesque:laminate)."
  (lambda (omega alpha &optional axes)
    (let ((axis *first-axis-or-nil*))
      (if (floatp axis)
	  ;; laminate in the case of a fractional axis argument
	  (laminate alpha omega (ceiling axis))
	  ;; simply stack the arrays if there is no axis argument or it's an integer
	  (catenate alpha omega (or axis (max 0 (1- (max (rank alpha) (rank omega))))))))))

(defun catenate-on-first (index-origin)
  "Wrapper for [⍪ catenate first]; distinct from (catenate-arrays) because it does not provide the laminate functionality."
  (lambda (omega alpha &optional axes)
    (if (and (vectorp alpha) (vectorp omega))
	(if (and *first-axis-or-nil* (< 0 *first-axis-or-nil*))
	    (error (concatenate 'string "Specified axis is greater than 1, vectors"
				" have only one axis along which to catenate."))
	    (if (and axes (> 0 *first-axis-or-nil*))
		(error (format nil "Specified axis is less than ~a." index-origin))
		(catenate alpha omega 0)))
	(if (or (not axes)
		(integerp (first axes)))
	    (catenate alpha omega (or *first-axis-or-nil* 0))))))

(defun section-array (index-origin metadata-symbol &optional inverse)
  "Wrapper for (aplesque:section) used for [↑ take] and [↓ drop]."
  (lambda (omega alpha &optional axes)
    (let* ((alpha-index alpha)
	   (alpha (if (arrayp alpha)
		      alpha (vector alpha)))
	   (output (section omega
			    (if axes (let ((dims (make-array
						  (rank omega)
						  :initial-contents (if inverse (loop :for i :below (rank omega)
										   :collect 0)
									(dims omega))))
					   (spec-axes (first axes)))
				       (if (integerp spec-axes)
					   (setf (aref dims (- spec-axes index-origin)) (aref alpha 0))
					   (if (vectorp spec-axes)
					       (loop :for ax :across spec-axes :for ix :from 0
						  :do (setf (aref dims (- ax index-origin))
							    (aref alpha ix)))))
				       dims)
				alpha)
			    :inverse inverse :populator (build-populator metadata-symbol omega))))
      ;; if the resulting array is empty and the original array prototype was an array, set the
      ;; empty array prototype accordingly
      (if (and (= 0 (size output))
	       (not inverse) (arrayp (row-major-aref omega 0)))
	  (set-workspace-item-meta metadata-symbol output
				   :eaprototype
				   (make-prototype-of (funcall (if (= 0 (rank omega)) #'identity #'aref)
							       (row-major-aref omega 0)))))
      output)))

(defun pick (index-origin)
  "Fetch an array element, within successively nested arrays for each element of the left argument."
  (lambda (omega alpha)
    (labels ((pick-point (point input)
	       (if (is-unitary point)
		   (let ((point (disclose point)))
		     ;; if this is the last level of nesting specified, fetch the element
		     (if (not (arrayp point))
			 (aref input (- point index-origin))
			 (if (vectorp point)
			     (apply #'aref input (loop :for p :across point :collect (- p index-origin)))
			     (error "Coordinates for ⊃ must be expressed by scalars or vectors."))))
		   ;; if there are more elements of the left argument left to go, recurse on the element designated
		   ;; by the first element of the left argument and the remaining elements of the point
		   (pick-point (if (< 2 (length point))
				   (make-array (1- (length point))
					       :initial-contents (loop :for i :from 1 :to (1- (length point))
								    :collect (aref point i)))
				   (aref point 1))
			       (disclose (pick-point (aref point 0) input))))))
      ;; TODO: swap out the vector-based point for an array-based point
      (if (= 1 (array-total-size omega))
	  (error "Right argument to dyadic [⊃ pick] may not be unitary.")
	  (pick-point alpha omega)))))

(defun expand-array (degrees input axis metadata-symbol &key (compress-mode))
  "Wrapper for (aplesque:expand) implementing [/ replicate] and [\ expand]."
  (let ((output (expand degrees input axis :compress-mode compress-mode
			:populator (build-populator metadata-symbol input))))
    (if (and (= 0 (size output)) (arrayp input) (arrayp (row-major-aref input 0)))
	(set-workspace-item-meta metadata-symbol output
				 :eaprototype
				 (make-prototype-of (funcall (if (= 0 (rank input)) #'identity #'aref)
							     (row-major-aref input 0)))))
    output))

(defun array-intersection (omega alpha)
  "Return a vector of values common to two arrays. Used to implement [∩ intersection]."
  (let ((omega (enclose-atom omega))
	(alpha (enclose-atom alpha)))
    (if (or (not (vectorp alpha))
	    (not (vectorp omega)))
	(error "Arguments to [∩ intersection] must be vectors.")
	(let* ((match-count 0)
	       (matches (loop :for item :across alpha :when (find item omega :test #'array-compare)
			   :collect item :and :do (incf match-count))))
	  (make-array (list match-count) :initial-contents matches
		      :element-type (type-in-common (element-type alpha) (element-type omega)))))))

(defun unique (omega)
  "Return a vector of unique values in an array. Used to implement [∪ unique]."
  (if (not (arrayp omega)) (vector omega)
      (let ((vector (if (vectorp omega)
			omega (re-enclose omega (make-array (1- (rank omega))
							    :element-type 'fixnum
							    :initial-contents
							    (loop :for i :from 1 :to (1- (rank omega))
							       :collect i))))))
	(let ((uniques) (unique-count 0))
	  (loop :for item :across vector :when (not (find item uniques :test #'array-compare))
	     :do (setq uniques (cons item uniques)
		       unique-count (1+ unique-count)))
	  (funcall (lambda (result) (if (vectorp omega) result (mix-arrays 1 result)))
		   (make-array unique-count :element-type (element-type vector)
			       :initial-contents (reverse uniques)))))))

(defun array-union (omega alpha)
  "Return a vector of unique values from two arrays. Used to implement [∪ union]."
  (let ((omega (enclose-atom omega))
	(alpha (enclose-atom alpha)))
    (if (or (not (vectorp alpha))
	    (not (vectorp omega)))
	(error "Arguments must be vectors.")
	(let* ((unique-count 0)
	       (uniques (loop :for item :across omega :when (not (find item alpha :test #'array-compare))
			   :collect item :and :do (incf unique-count))))
	  (catenate alpha (make-array unique-count :initial-contents uniques
				      :element-type (type-in-common (element-type alpha)
								    (element-type omega)))
		    0)))))

(defun unique-mask (array)
  "Return a 1 for each value encountered the first time in an array, 0 for others. Used to implement monadic [≠ unique mask]."
  (let ((output (make-array (first (dims array)) :element-type 'bit :initial-element 1))
	(displaced (if (< 1 (rank array)) (make-array (rest (dims array))
						      :displaced-to array
						      :element-type (element-type array))))
	(uniques) (increment (reduce #'* (rest (dims array)))))
    (dotimes (x (first (dims array)))
      (if (and displaced (< 0 x))
	  (setq displaced (make-array (rest (dims array)) :element-type (element-type array)
				      :displaced-to array :displaced-index-offset (* x increment))))
      (if (member (or displaced (aref array x)) uniques :test #'array-compare)
	  (setf (aref output x) 0)
	  (setf uniques (cons (if displaced (make-array (rest (dims array)) :displaced-to array
							:element-type (element-type array)
							:displaced-index-offset (* x increment))
				  (aref array x))
			      uniques))))
    output))

(defun permute-array (index-origin)
  "Wraps (aops:permute) to permute an array, rearranging the axes in a given order or reversing them if no order is given. Used to implement monadic and dyadic [⍉ permute]."
  (lambda (omega &optional alpha)
    (if (not (arrayp omega))
	omega (aops:permute (if alpha (loop :for i :across (enclose-atom alpha) :collect (- i index-origin))
				(loop :for i :from (1- (rank omega)) :downto 0 :collect i))
			    omega))))

(defun matrix-inverse (omega)
  "Invert a matrix. Used to implement monadic [⌹ matrix inverse]."
  (if (not (arrayp omega))
      (/ omega)
      (if (< 2 (rank omega))
	  (error "Matrix inversion only works on arrays of rank 2 or 1.")
	  (funcall (if (and (= 2 (rank omega)) (reduce #'= (dims omega)))
		       #'invert-matrix #'left-invert-matrix)
		   omega))))

(defun matrix-divide (omega alpha)
  "Divide two matrices. Used to implement dyadic [⌹ matrix divide]."
  (array-inner-product (invert-matrix omega) alpha (lambda (arg1 arg2) (apply-scalar #'* arg1 arg2))
		       #'+))

(defun encode (omega alpha &optional inverse)
  "Encode a number or array of numbers as per a given set of bases. Used to implement [⊤ encode]."
  (let* ((omega (if (arrayp omega)
		    omega (enclose-atom omega)))
	 (alpha (if (arrayp alpha)
		    alpha (if (not inverse)
			      ;; if the encode is an inverted decode, extend a
			      ;; scalar left argument to the appropriate degree
			      (enclose-atom alpha) (let ((max-omega 0))
						 (if (arrayp omega)
						     (dotimes (i (size omega))
						       (setq max-omega
							     (max max-omega (row-major-aref omega i))))
						     (setq max-omega omega))
						 (make-array (1+ (floor (log max-omega) (log alpha)))
							     :initial-element alpha)))))
	 (odims (dims omega)) (adims (dims alpha))
	 (last-adim (first (last adims)))
	 (out-coords (loop :for i :below (+ (- (rank alpha) (count 1 adims))
					    (- (rank omega) (count 1 odims))) :collect 0))
	 (out-dims (append (loop :for dim :in adims :when (< 1 dim) :collect dim)
			   (loop :for dim :in odims :when (< 1 dim) :collect dim)))
	 (output-maxval (if out-dims (let ((displaced (make-array (size alpha) :displaced-to alpha
								  :element-type (element-type alpha))))
				       (loop :for i :across displaced :maximizing i))))
	 (output (if out-dims (make-array out-dims :element-type (list 'integer 0 output-maxval))))
	 (dxc))
    (flet ((rebase (base-coords number)
	     (let ((operand number) (last-base 1)
		   (base 1) (component 1) (element 0))
	       (loop :for index :from (1- last-adim) :downto (first (last base-coords))
		  :do (setq last-base base
			    base (* base (apply #'aref alpha (append (butlast base-coords 1)
								     (list index))))
			    component (if (= 0 base)
					  operand (* base (nth-value 1 (floor (/ operand base)))))
			    operand (- operand component)
			    element (/ component last-base)))
	       element)))
      (across alpha (lambda (aelem acoords)
		      (declare (ignore aelem)) ;; (dynamic-extent acoords))
		      (across omega (lambda (oelem ocoords)
				      ;; (declare (dynamic-extent oelem ocoords))
				      (setq dxc 0)
				      (if out-dims
					  (progn (loop :for dx :below (length acoords) :when (< 1 (nth dx adims))
						    :do (setf (nth dxc out-coords) (nth dx acoords)
							      dxc (1+ dxc)))
						 (loop :for dx :below (length ocoords) :when (< 1 (nth dx odims))
						    :do (setf (nth dxc out-coords) (nth dx ocoords)
							      dxc (1+ dxc)))))
				      (if out-dims (setf (apply #'aref output out-coords)
							 (rebase acoords oelem))
					  (setq output (rebase acoords oelem)))))))
      output)))

(defun decode (omega alpha)
  "Decode an array of numbers as per a given set of bases. Used to implement [⊥ decode]."
  (let* ((omega (if (arrayp omega)
		    omega (enclose-atom omega)))
	 (alpha (if (arrayp alpha)
		    alpha (enclose-atom alpha)))
	 (odims (dims omega)) (adims (dims alpha))
	 (last-adim (first (last adims)))
	 (rba-coords (loop :for i :below (rank alpha) :collect 0))
	 (rbo-coords (loop :for i :below (rank omega) :collect 0))
	 (out-coords (loop :for i :below (max 1 (+ (1- (rank alpha)) (1- (rank omega)))) :collect 0))
	 (out-dims (append (butlast adims 1) (rest odims)))
	 (maximum-value (if out-dims (if (vectorp alpha)
					 (reduce #'* (loop :for a :across alpha :collect a))
					 (let ((max 0)
					       (vector-length (first (last (dims alpha)))))
					   (dotimes (i (reduce #'* (butlast (dims alpha))))
					     (let ((items
						    (loop :for n :below vector-length
						       :collect (row-major-aref
								 alpha (+ n (* i vector-length))))))
					       (setq max (max max (reduce #'* items)))))
					   max))))
	 (output (if out-dims (make-array out-dims :element-type (list 'integer 0 maximum-value))))
	 (dxc))
    (flet ((rebase (base-coords number-coords)
	     (let ((base 1) (result 0) (bclen (length base-coords)))
	       (loop :for i :from 0 :to (- bclen 2)
		  :do (setf (nth i rba-coords) (nth i base-coords)))
	       (loop :for i :from 1 :to (1- (length number-coords))
		  :do (setf (nth i rbo-coords) (nth i number-coords)))
	       (if (and (not (is-unitary base-coords))
			(not (is-unitary number-coords))
			(/= (first odims) (first (last adims))))
		   (error "If neither argument to ⊥ is scalar, the first dimension of the right argument~a"
			  " must equal the last dimension of the left argument.")
		   (loop :for index :from (if (< 1 last-adim) (1- last-adim) (1- (first odims)))
		      :downto 0 :do (setf (nth 0 rbo-coords) (if (< 1 (first odims)) index 0)
					  (nth (1- bclen) rba-coords) (if (< 1 last-adim) index 0))
			(incf result (* base (apply #'aref omega rbo-coords)))
			(setq base (* base (apply #'aref alpha rba-coords)))))
	       result)))
      (across alpha (lambda (aelem acoords)
		      (declare (ignore aelem)) ;; (dynamic-extent acoords))
		      (across omega (lambda (oelem ocoords)
				      (declare (ignore oelem)) ;; (dynamic-extent ocoords))
				      (setq dxc 0)
				      (dotimes (dx (1- (length acoords)))
					(setf (nth dxc out-coords) (nth dx acoords)
					      dxc (1+ dxc)))
				      (if ocoords (loop :for dx :from 1 :to (1- (length ocoords))
						     :do (setf (nth dxc out-coords) (nth dx ocoords)
							       dxc (1+ dxc))))
				      (if out-dims (setf (apply #'aref output (or out-coords '(0)))
							    (rebase acoords ocoords))
					  (setq output (rebase acoords ocoords))))
			      :elements (loop :for i :below (rank omega) :collect (if (= i 0) 0)))))
      :elements (loop :for i :below (rank alpha) :collect (if (= i (1- (rank alpha))) 0)))
    output))

(defun left-invert-matrix (in-matrix)
  "Perform left inversion of matrix. Used to implement [⌹ matrix inverse]."
  (let* ((input (if (= 2 (rank in-matrix))
		    in-matrix (make-array (list (length in-matrix) 1))))
	 (input-displaced (if (/= 2 (rank in-matrix))
			      (make-array (list 1 (length in-matrix)) :element-type (element-type input)
					  :displaced-to input))))
    (if input-displaced (xdotimes input (i (length in-matrix)) (setf (row-major-aref input i)
								     (aref in-matrix i))))
    (let ((result (array-inner-product (invert-matrix (array-inner-product (or input-displaced
									       (aops:permute '(1 0) input))
									   input #'* #'+))
				       (or input-displaced (aops:permute '(1 0) input))
				       #'* #'+)))
      (if (= 1 (rank in-matrix))
	  (make-array (size result) :element-type (element-type result) :displaced-to result)
	  result))))

(defun format-array (print-precision)
  "Use (aplesque:array-impress) to print an array and return the resulting character array, with the option of specifying decimal precision. Used to implement monadic and dyadic [⍕ format]."
  (lambda (omega &optional alpha)
    (if (and alpha (not (integerp alpha)))
	(error (concatenate 'string "The left argument to ⍕ must be an integer specifying"
			    " the precision at which to print floating-point numbers.")))
    (array-impress omega :collate t
		   :segment (lambda (number &optional segments)
			      (aplesque::count-segments number (if alpha (- alpha) print-precision)
							segments))
		   :format (lambda (number &optional segments rps)
			     (print-apl-number-string number segments print-precision alpha rps)))))

(defun generate-index-array (array)
  "Given an array, generate an array of the same shape whose each cell contains its row-major index."
  (let* ((is-scalar (= 0 (rank array)))
	 (array (if is-scalar (aref array) array))
	 (output (make-array (dims array) :element-type (list 'integer 0 (size array)))))
    (xdotimes output (i (size array)) (setf (row-major-aref output i) i))
    (funcall (if (not is-scalar) #'identity (lambda (o) (make-array nil :initial-element o)))
	     output)))

(defun generate-selection-form (form space)
  "Generate a selection form for use with selective-assignment, i.e. (3↑x)←5."
  (let ((value-symbol) (set-form) (choose-unpicked)
	(value-placeholder (gensym)))
    (labels ((val-wssym (s)
	       (or (symbolp s)
		   (and (listp s) (eql 'inws (first s))
			(symbolp (second s)))))
	     (sfun-aliased (symbol)
	       (let ((alias-entry (get-workspace-alias space symbol)))
		 (and (symbolp symbol)
		      (characterp alias-entry)
		      (member alias-entry '(#\↑ #\↓ #\/ #\⊃) :test #'char=))))
	     (atin-aliased (symbol)
	       (let ((alias-entry (get-workspace-alias space symbol)))
		 (and (symbolp symbol)
		      (characterp alias-entry)
		      (char= #\⌷ alias-entry))))
	     (disc-aliased (symbol)
	       (let ((alias-entry (get-workspace-alias space symbol)))
		 (and (symbolp symbol)
		      (characterp alias-entry)
		      (char= #\⊃ alias-entry))))
	     (process-form (f)
	       (match f ((list* 'apl-call fn-symbol fn-form first-arg rest)
			 ;; recursively descend through the expression in search of an expression containing
			 ;; the variable and one of the four functions usable for selective assignment
			 (if (and (listp first-arg) (eql 'apl-call (first first-arg)))
			     `(apl-call ,fn-symbol ,fn-form ,(process-form first-arg) ,@rest)
			     (if (or (eql fn-symbol '⌷)
				     (atin-aliased fn-symbol))
				 ;; assigning to a [⌷ at index] form is an just an alternate version
				 ;; of assigning to axes, like x[1;3]←5
				 (let ((form-copy (copy-list fn-form)))
				   (setf (second form-copy)
					 (append (second form-copy) (list value-placeholder))
					 (third form) form-copy
					 set-form (fourth form))
				   form)
				 (progn (if (or (member fn-symbol '(↑ ↓ / ⊃))
						(sfun-aliased fn-symbol))
					    (if (val-wssym first-arg)
						(setq value-symbol first-arg)
						(if (and (eql 'achoose (first first-arg))
							 (val-wssym (second first-arg)))
						    (if (or (eql '⊃ fn-symbol)
							    (disc-aliased fn-symbol))
							(setq value-symbol first-arg
							      set-form
							      (append first-arg
								      (list :set value-placeholder)))
							(setq value-symbol (second first-arg)
							      choose-unpicked t)))))
					(if value-symbol
					    `(apl-call ,fn-symbol ,fn-form
						       ,(if (not choose-unpicked)
							    value-placeholder
							    (append (list 'achoose value-placeholder)
								    (cddr first-arg)))
						       ,@rest)))))))))
      (let ((form-out (process-form form)))
	(values form-out value-symbol value-placeholder set-form)))))

(defun assign-selected (array indices values)
  "Assign array values selected using one of the functions [↑ take], [↓ drop], [\ expand] or [⊃ pick]."
  (if (or (= 0 (rank values))
	  (and (= (rank indices) (rank values))
	       (loop :for i :in (dims indices) :for v :in (dims values) :always (= i v))))
      ;; if the data to be assigned is not a scalar value, a new array must be created to ensure
      ;; that the output array will be compatible with all assigned and original values
      (let* ((to-copy-input (not (and (= 0 (rank values))
				      (or (eq t (element-type array))
					  (and (listp (type-of array))
					       (or (eql 'simple-vector (first (type-of array)))
						   (and (eql 'simple-array (first (type-of array)))
							(typep values (second (type-of array))))))))))
	     (output (if (not to-copy-input)
			 array (make-array (dims array) :element-type (if (/= 0 (rank values))
									  t (assign-element-type values)))))
	     (assigned-indices (if to-copy-input (make-array (size array) :element-type '(unsigned-byte 8)
							     :initial-element 0))))
	;; TODO: is assigning bits slow?
	;; iterate through the items to be assigned and, if an empty array has been initialized for
	;; the output, store the indices that have been assigned to new data
	(xdotimes output (i (size indices))
	  (setf (row-major-aref output (row-major-aref indices i))
		(if (= 0 (rank values)) values (row-major-aref values i)))
	  (if to-copy-input (setf (aref assigned-indices (row-major-aref indices i)) 1)))
	;; if the original array was assigned to just return it, or if a new array was created
	;; iterate through the old array and copy the non-assigned data to the output
	(if to-copy-input (xdotimes output (i (size array))
			    (if (= 0 (aref assigned-indices i))
				(setf (row-major-aref output i) (row-major-aref array i)))))
	output)
      (error "Area of array to be reassigned does not match shape of values to be assigned.")))

(defun match-lexical-function-identity (glyph)
  "Find the identity value of a lexical function based on its character."
  (second (assoc glyph '((#\+ 0) (#\- 0) (#\× 1) (#\÷ 1) (#\⋆ 1) (#\* 1) (#\! 1)
			 (#\< 0) (#\≤ 1) (#\= 1) (#\≥ 1) (#\> 0) (#\≠ 0) (#\| 0)
			 (#\^ 1) (#\∧ 1) (#\∨ 0) (#\⊤ 0) (#\∪ #()) (#\⌽ 0) (#\⊖ 0)
			 (#\⌈ most-negative-long-float) (#\⌊ most-positive-long-float))
		 :test #'char=)))

(defun operate-reducing (function function-glyph axis &optional last-axis)
  "Reduce an array along a given axis by a given function, returning function identites when called on an empty array dimension. Used to implement the [/ reduce] operator."
  (lambda (omega)
    (if (not (arrayp omega))
	omega (if (= 0 (size omega))
		  (or (and (= 1 (rank omega))
			   (match-lexical-function-identity (aref function-glyph 0)))
		      (make-array 0))
		  (if (= 0 (rank omega))
		      (make-array nil :initial-element (funcall function (aref omega)
								(aref omega)))
		      (let* ((odims (dims omega))
			     (axis (or axis (if (not last-axis) 0 (max 0 (1- (rank omega))))))
			     (rlen (nth axis odims))
			     (increment (reduce #'* (nthcdr (1+ axis) odims)))
			     (output (make-array (loop :for dim :in odims :for dx :from 0
						    :when (/= dx axis) :collect dim))))
			(xdotimes output (i (size output))
			  (declare (optimize (safety 1)))
			  (let ((value))
			    (loop :for ix :from (1- rlen) :downto 0
			       :do (let ((item (row-major-aref
						omega (+ (* ix increment)
							 (if (= 1 increment)
							     0 (* (floor i increment)
								  (- (* increment rlen) increment)))
							 (if (/= 1 increment) i (* i rlen))))))
				     (setq value (if (not value) item (funcall function (disclose value)
									       (disclose item))))))
			    (setf (row-major-aref output i) value)))
			(disclose-atom output)))))))

(defun operate-scanning (function axis &optional last-axis inverse)
  "Scan a function across an array along a given axis. Used to implement the [\ scan] operator with an option for inversion when used with the [⍣ power] operator taking a negative right operand."
  (lambda (omega)
    (if (not (arrayp omega))
	omega (let* ((odims (dims omega))
		     (axis (or axis (if (not last-axis) 0 (1- (rank omega)))))
		     (rlen (nth axis odims))
		     (increment (reduce #'* (nthcdr (1+ axis) odims)))
		     (output (make-array odims)))
		(xdotimes output (i (size output))
		  (declare (optimize (safety 1)))
		  (let ((value)	(vector-index (mod (floor i increment) rlen)))
		    (if inverse
			(let ((original (disclose (row-major-aref
						   omega (+ (mod i increment)
							    (* increment vector-index)
							    (* increment rlen
							       (floor i (* increment rlen))))))))
			  (setq value (if (= 0 vector-index)
					  original
					  (funcall function original
						   (disclose
						    (row-major-aref
						     omega (+ (mod i increment)
							      (* increment (1- vector-index))
							      (* increment rlen
								 (floor i (* increment rlen))))))))))
			(loop :for ix :from vector-index :downto 0
			   :do (let ((original (row-major-aref
						omega (+ (mod i increment) (* ix increment)
							 (* increment rlen (floor i (* increment rlen)))))))
				 (setq value (if (not value) (disclose original)
						 (funcall function value (disclose original)))))))
		    (setf (row-major-aref output i) value)))
		output))))

(defun operate-each (function-monadic function-dyadic)
  "Generate a function applying a function to each element of an array. Used to implement [¨ each]."
  (let (;; (function-monadic (lambda (o) (funcall function-monadic o)))
   	(function-dyadic (lambda (o a) (funcall function-dyadic (disclose o) (disclose a)))))
    (flet ((wrap (i) (if (not (and (arrayp i) (< 0 (rank i))))
			 i (make-array nil :initial-element i))))
      (lambda (omega &optional alpha)
	(let* ((oscalar (if (is-unitary omega) omega))
	       (ascalar (if (is-unitary alpha) alpha))
	       (odims (dims omega)) (adims (dims alpha))
	       (orank (rank omega)) (arank (rank alpha)))
	  (if (not (or oscalar ascalar (not alpha)
		       (and (= orank arank)
			    (loop :for da :in adims :for do :in odims :always (= da do)))))
	      (error "Mismatched left and right arguments to [¨ each].")
	      (let* ((output-dims (dims (if oscalar alpha omega)))
		     (output (if (not (and oscalar (or ascalar (not alpha))))
				 (make-array output-dims))))
		(if alpha (if (and oscalar ascalar)
			      (setq output (funcall function-dyadic omega alpha))
			      (xdotimes (if oscalar alpha omega) (i (size (if oscalar alpha omega)))
				(setf (row-major-aref output i)
				      (funcall function-dyadic (or oscalar (row-major-aref omega i))
					       (or ascalar (row-major-aref alpha i))))))
		    (if oscalar (setq output (funcall function-monadic oscalar))
			(xdotimes omega (i (size omega))
			  (setf (row-major-aref output i)
				(funcall function-monadic (row-major-aref omega i))))))
		output)))))))

(defun operate-grouping (function index-origin)
  "Generate a function applying a function to items grouped by a criterion. Used to implement [⌸ key]."
  (lambda (omega &optional alpha)
    (let* ((keys (or alpha omega))
	   (key-test #'equalp)
	   (indices-of (lambda (item vector)
			 (loop :for li :below (length vector)
			    :when (funcall key-test item (aref vector li))
			    :collect (+ index-origin li))))
	   (key-table (make-hash-table :test key-test))
	   (key-list))
      (dotimes (i (size keys))
	(let ((item (row-major-aref keys i)))
	  ;; (declare (dynamic-extent item))
	  (if (loop :for key :in key-list :never (funcall key-test item key))
	      (setq key-list (cons item key-list)))
	  (setf (gethash item key-table)
		(cons (row-major-aref omega i)
		      (gethash item key-table)))))
      (let ((item-sets (loop :for key :in (reverse key-list)
			  :collect (funcall function
					    (let ((items (if alpha (gethash key key-table)
							     (funcall indices-of key keys))))
					      (make-array (length items)
							  :initial-contents (reverse items)))
					    key))))
	(mix-arrays 1 (apply #'vector item-sets))))))

(defun operate-composed (right right-fn-monadic right-fn-dyadic
			 left left-fn-monadic left-fn-dyadic is-confirmed-monadic)
  "Generate a function by linking together two functions or a function curried with an argument. Used to implement [∘ compose]."
  (let ((fn-right (or right-fn-monadic right-fn-dyadic))
	(fn-left (or left-fn-monadic left-fn-dyadic)))
    (lambda (omega &optional alpha)
      (if (and fn-right fn-left)
	  (let ((processed (funcall right-fn-monadic omega)))
	    (if is-confirmed-monadic (funcall left-fn-monadic processed)
		(if alpha (funcall left-fn-dyadic processed alpha)
		    (funcall left-fn-monadic processed))))
	  (if alpha (error "This function does not take a left argument.")
	      (funcall (or right-fn-dyadic left-fn-dyadic)
		       (if (not fn-right) right omega)
		       (if (not fn-left) left omega)))))))

(defun operate-at-rank (rank function-monadic function-dyadic)
  "Generate a function applying a function to sub-arrays of the arguments. Used to implement [⍤ rank]."
  (lambda (omega &optional alpha)
    (let* ((odims (dims omega)) (adims (dims alpha))
	   (osize (size omega)) (asize (size alpha))
	   (rank (if (not (arrayp rank))
		     (make-array 3 :initial-element rank)
		     (if (= 2 (size rank))
			 (make-array 3 :initial-contents (list (aref rank 1) (aref rank 0) (aref rank 1)))
			 (if (= 3 (size rank))
			     rank (if (or (< 1 (rank rank)) (< 3 (size rank)))
				      (error "Right operand of [⍤ rank] must be a scalar integer or ~a"
					     "integer vector no more than 3 elements long."))))))
	   (ocrank (aref rank 2))
	   (acrank (aref rank 1))
	   (omrank (aref rank 0))
	   (odivs (make-array (subseq odims 0 (- (rank omega) (if alpha ocrank omrank)))))
	   (odiv-dims (subseq odims (- (rank omega) (if alpha ocrank omrank))))
	   (odiv-size (reduce #'* odiv-dims))
	   (adivs (if alpha (make-array (subseq adims 0 (- (rank alpha) acrank)))))
	   (adiv-dims (if adivs (subseq adims (- (rank alpha) acrank))))
	   (adiv-size (if alpha (reduce #'* adiv-dims)))
	   (odiv-interval (/ osize odiv-size))
	   (adiv-interval (if alpha (/ asize adiv-size))))
      (flet ((generate-divs (div-array ref-array div-dims div-size)
      	       (xdotimes div-array (i (size div-array))
      		 (setf (row-major-aref div-array i)
      		       (if (= 0 (rank div-array)) ref-array
      			   (make-array div-dims :element-type (element-type ref-array)
      				       :displaced-to ref-array :displaced-index-offset (* i div-size)))))))
      	(generate-divs odivs omega odiv-dims odiv-size)
      	(if alpha (progn (generate-divs adivs alpha adiv-dims adiv-size)
			 (let ((output (funcall function-dyadic odivs adivs)))
			   (if ;; (or (= 0 (rank odivs)) (= 0 (rank adivs))
			    ;; 	   (= 0 (rank (row-major-aref odivs 0)))
			    ;; 	   (= 0 (rank (row-major-aref adivs 0))))
			    ;; TODO: what's a better heuristic for deciding whether to disclose?
			    t (xdotimes output (i (size output))
				(setf (row-major-aref output i) (disclose (row-major-aref output i)))))
			   (mix-arrays (max (rank odivs) (rank adivs))
				       output)))
	    (let ((output (make-array (dims odivs))))
	      (xdotimes output (i (size output))
		(setf (row-major-aref output i) (funcall function-monadic (row-major-aref odivs i))))
	      (mix-arrays (rank output) output)))))))

(defun operate-atop (right-fn-monadic right-fn-dyadic left-fn-monadic)
  (lambda (omega &optional alpha)
    (if alpha (funcall left-fn-monadic (funcall right-fn-dyadic omega alpha))
	(funcall left-fn-monadic (funcall right-fn-monadic omega)))))

(defun operate-to-power (power function-retriever)
  "Generate a function applying a function to a value and successively to the results of prior iterations a given number of times. Used to implement [⍣ power]."
  (lambda (omega &optional alpha)
    (let ((arg omega) (function (funcall function-retriever alpha (> 0 power))))
      (dotimes (index (abs power))
	(setq arg (if alpha (funcall function arg alpha)
		      (funcall function arg))))
      arg)))

(defun operate-until (op-right op-left-monadic op-left-dyadic)
  "Generate a function applying a function to a value and successively to the results of prior iterations until a condition is net. Used to implement [⍣ power]."
  (lambda (omega &optional alpha)
    (declare (ignorable alpha))
    (let ((arg omega) (prior-arg omega))
      (loop :for index :from 0 :while (or (= 0 index)
					  (= 0 (funcall op-right prior-arg arg)))
	 :do (setq prior-arg arg
		   arg (if alpha (funcall op-left-dyadic arg alpha)
			   (funcall op-left-monadic arg))))
      arg)))

(defun operate-at (left right left-fn-m left-fn-d right-fn)
  "Generate a function applying a function at indices in an array specified by a given index or meeting certain conditions. Used to implement [@ at]."
  (lambda (omega &optional alpha)
    (declare (ignorable alpha))
    (choose omega (if (not right-fn)
		      (append (list (apl-call - (scalar-function -) right 1))
			      (loop :for i :below (1- (rank omega)) :collect nil)))
	    :set (if (not (or left-fn-m left-fn-d)) left)
	    :set-by (if (or left-fn-m left-fn-d right-fn)
			(lambda (old &optional new)
			  (declare (ignorable new))
			  (if (and right-fn (= 0 (funcall right-fn old)))
			      old (if (not (or left-fn-m left-fn-d))
				      new (if alpha (funcall left-fn-d old alpha)
					      (funcall left-fn-m old)))))))))

(defun operate-stenciling (right-value left-function)
  "Generate a function applying a function via (aplesque:stencil) to an array. Used to implement [⌺ stencil]."
  (lambda (omega)
    (flet ((iaxes (value index) (loop :for x :below (rank value) :for i :from 0
				   :collect (if (= i 0) index nil))))
      (if (not (or (and (< 2 (rank right-value))
			(error "The right operand of [⌺ stencil] may not have more than 2 dimensions."))
		   (and (not left-function)
			(error "The left operand of [⌺ stencil] must be a function."))))
	  (let ((window-dims (if (not (arrayp right-value))
				 (vector right-value)
				 (if (= 1 (rank right-value))
				     right-value (choose right-value (iaxes right-value 0)))))
		(movement (if (not (arrayp right-value))
			       (vector 1)
			       (if (= 2 (rank right-value))
				   (choose right-value (iaxes right-value 1))
				   (make-array (length right-value) :element-type 'fixnum
					       :initial-element 1)))))
	    (merge-arrays (stencil omega left-function window-dims movement) :nesting nil))))))
