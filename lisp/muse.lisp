;;;; muse.lisp
;;;
;;; Parse the Emacs Muse format from the Muse project, as found at:
;;;
;;;   http://mwolson.org/projects/EmacsMuse.html

(in-package #:tapoueh)

(defparameter *muse-pathname-type* "muse"
  "The file extension we use to store Muse files")

(defparameter *image-directory*
  (asdf:system-relative-pathname :tapoueh "../images/"))

(defparameter *image-type-list*
  (remove-if
   #'null
   (remove-duplicates (mapcar #'pathname-type
			      (fad:list-directory *image-directory*))
		      :test #'string=)))

;;
;; Document data structure, pretty loose
;;
(defstruct
    (muse
      (:constructor make-muse)
      (:constructor make-muse-article (&key
				       pathname mod-timestamp
				       author title date tags desc
				       contents
				       &aux (timestamp (when date
							 (parse-date date))))))
  pathname mod-timestamp author title date timestamp tags desc contents)

(defmethod muse-article-p ((document muse))
  "Return a generalized boolean true when DOCUMENT is a Muse Article.

   A Muse Article is a Muse Document with all the directives given, so that
   none of the meta-data slots are nil."
  (and (muse-author document)
       (muse-title  document)
       (muse-date   document)
       (muse-tags   document)))

;;; a .muse file is a "document"
(defmethod same-document-p ((d1 muse) (d2 muse))
  "Compare d1 and d2 slots"
  (and (equalp (muse-author d1) (muse-author d2))
       (equalp (muse-title d1) (muse-title d2))
       (equalp (muse-date d1) (muse-date d2))
       (local-time:timestamp= (muse-timestamp d1) (muse-timestamp d2))
       (tree-equal (muse-tags d1) (muse-tags d2) :test #'equal)
       (tree-equal (muse-contents d1) (muse-contents d2) :test #'equal)))

(defmethod file-newer-p ((m muse))
  "True when the modification time of p1 is before the p2 one"
  (local-time:timestamp< (muse-mod-timestamp m)
			 (local-time:universal-to-timestamp
			  (file-write-date (muse-pathname m)))))

(defmethod to-html ((document muse))
  "Produce the HTML of given Document"
  (eval `(with-html-output-to-string (s)
	   ,@(muse-contents document))))

;;; a .muse file with the 4 directives is an "article"
(defmethod sort-articles ((a1 muse) (a2 muse)
			  &key
			    (test #'local-time:timestamp<)
			    (key 'timestamp))
  (let ((t1 (slot-value a1 key))
	(t2 (slot-value a2 key)))
    (when (and t1 t2)
      (funcall test t1 t2))))

(defun parse-muse-article (pathname)
  "Parse the Muse article at PATHNAME and return a muse structure."
  (let ((article (parse 'article (slurp-file-into-string pathname))))
    (setf (muse-pathname article) pathname)
    (setf (muse-mod-timestamp article)
	  (local-time:universal-to-timestamp (file-write-date pathname)))
    article))

(defun parse-muse-directives (pathname)
  "Only parse the Muse directives, not the whole document"
  (let ((document
	 (parse 'directives (slurp-file-into-string pathname) :junk-allowed t)))
    (if document
	(progn
	  (setf (muse-pathname document) pathname)
	  (setf (muse-mod-timestamp document)
		(local-time:universal-to-timestamp (file-write-date pathname)))
	  document)
	(make-muse :pathname pathname))))

(defun muse-file-type-p (pathname)
  "Returns a generalized boolean true when pathname extension is .muse"
  (string= (pathname-type pathname) *muse-pathname-type*))