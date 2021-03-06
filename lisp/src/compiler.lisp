;;;
;;; Compile into a static website
;;;

(in-package #:tapoueh)

(defun blog-index-script-name (pathname &optional (root *blog-directory*))
  "Return the /blog/path/to/index url from given PATHNAME"
  (concatenate 'string
	       "/blog"
	       (subseq (namestring pathname) (- (length (namestring root)) 1))))

(defun articles-tagged (tag documents)
  "Return the list of documents that have the given tag."
  (flet ((document-tagged-p (document)
	   (member tag (muse-tags document) :test #'string-equal)))

   (remove-if-not #'document-tagged-p documents)))

(defun write-html-file (html localname &key verbose name (type "html"))
  "Write a HTML file into *HTML-DIRECTORY* as localname."
  (let ((dest (expand-file-name-into localname *html-directory*
				     :name name
				     :type type)))
    (when verbose (format t "~a~%" dest))
    (ensure-directories-exist (directory-namestring dest))
    (with-open-file (s dest
		       :direction :output
		       :if-exists :supersede
		       :if-does-not-exist :create
		       :external-format :utf-8)
      (write-string html s))))

(defmacro with-html-file ((stream localname &key verbose name (type "html"))
                          &body body)
  "Run body within opened STREAM to the LOCALNAME file."
  (let ((dest (gensym "with-html-file-dest-")))
    `(let ((,dest (expand-file-name-into ,localname *html-directory*
                                         :name ,name
                                         :type ,type)))
       (when ,verbose (format t "~a~%" ,dest))
       (ensure-directories-exist (directory-namestring ,dest))
       (with-open-file (,stream ,dest
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create
                                :external-format :utf-8)
         ,@body))))

(defun compile-home-page (&key documents verbose)
  "Compile to *HTML-DIRECTORY* this site's home page"
  (let ((url "/")
	(html (render-reversed-index-page "/" documents)))
    (write-html-file html url :name "index" :verbose verbose)))

(defun compile-tags-cloud (&key documents verbose)
  "Compile the cloud tags JSON file."
  (let ((*blog-articles* (make-hash-table :test 'equal :size 1024)))
    ;; fill-in the hash table
    (loop
       for document in documents
       do (setf (gethash (muse-pathname document) *blog-articles*) document))

    (let ((json (render-tag-cloud)))
      (write-html-file json "/" :name "cloud" :type "json" :verbose verbose))
    ;; return how many documents where processed
    (hash-table-count *blog-articles*)))

(defun compile-site-documents (&key documents verbose)
  "Compile to *HTML-DIRECTORY* all the muse documents from *ROOT-DIRECTORY*."
  (loop
     for article in (or documents (find-muse-documents))
     do (let ((html (render-muse-document :article article)))
	  (write-html-file html (muse-url article) :verbose verbose))
     ;; return how many documents we wrote
     count article))

(defun compile-blog-indexes (&key documents verbose)
  "Compile to *HTML-DIRECTORY* all the blog indexes from *BLOG-DIRECTORY*"
  (let ((count 0))
    (labels ((in-path (document url)
	       (search url (namestring (muse-pathname document))))
	     (write-index-file (pathname)
	       (let* ((url  (blog-index-script-name pathname))
		      (docs (remove-if-not (lambda (doc) (in-path doc url))
					   documents))
		      (html (if (string= "/blog/" url)
				(render-reversed-index-page url documents 7)
				(render-index-page url docs))))
		 (incf count)
		 (write-html-file html url :name "index" :verbose verbose))))

      (fad:walk-directory *blog-directory* #'write-index-file
			  :directories t :test #'fad:directory-pathname-p))
    ;; return how many indexes we just built
    count))

(defun compile-blog-archives (&key documents verbose)
  "Compile to *HTML-DIRECTORY* the whole blog archives page."
  (let* ((url  "/blog/")
	 (len  (length documents))
	 (html (render-reversed-index-page url documents len)))
    (write-html-file html url :name "archives" :verbose verbose)
    ;; return how many documents we included
    len))

(defun compile-tags-lists (&key documents verbose)
  "Compile to *HTML-DIRECTORY* all the per-tag articles listings."
  (let ((tags))
    ;; prepare the list of known tags
    (loop
       for article in documents
       do (loop for tag in (muse-tags article)
	       do (pushnew tag tags :test #'string-equal)))
    ;; now export tags listings
    (loop
       for tag in (mapcar #'string-downcase tags)
       do (let* ((url  (format nil "/tags/~a" tag))
		 (html (render-tag-listing url (articles-tagged tag documents))))
	    (write-html-file html url :name tag :verbose verbose))
       ;; return how many files we wrote
       count tag)))

(defun compile-conf-index (&key documents verbose)
  "Compile to *HTML-DIRECTORY* the conferences index page."
  (let* ((url  "/conferences")
	 (len  (length documents))
	 (html (render-confs-index-page url (reverse documents))))
    (write-html-file html url :name "conferences" :verbose verbose)
    ;; return how many documents we included
    len))

(defun compile-projects-index (&key pgsql emacs verbose)
  "Compile to *HTML-DIRECTORY* the conferences index page."
  (let* ((url  "/conferences")
	 (len  (+ (length pgsql )(length emacs)))
	 (html (render-projects-index-page url pgsql emacs)))
    (write-html-file html url :name "projects" :verbose verbose)
    ;; return how many documents we included
    len))

(defun compile-rss-feeds (&key documents verbose
			    (tags '("tapoueh"
				    "common-lisp"
				    "postgresql"
				    "postgresqlfr"
				    "emacs"
				    "debian")))
  "Compile to *HTML-DIRECTORY* all the rss feeds"
  (loop
     for tag in (mapcar #'string-downcase tags)
     do (let* ((url  (format nil "/rss/~a" tag))
	       (docs (sort (articles-tagged tag documents)
			   #'muse-article-before-p)))
          (with-html-file (stream url :name tag :type "xml" :verbose verbose)
            (render-rss-feed stream url docs)))
     ;; return how many files we wrote
     count tag))

(defun compile-sitemap (&key documents verbose)
  "Compile a sitemap to *HTML-DIRECTORY*."
  (let* ((cl-who:*prologue* "<?xml version=\"1.0\" encoding=\"utf-8\"?>")
	 (sitemap
	 `(:urlset
	   :xmlns "http://www.sitemaps.org/schemas/sitemap/0.9"
	   :|xmlns:xsi| "http://www.w3.org/2001/XMLSchema-instance"
	   :|xsi:schemaLocation| "http://www.sitemaps.org/schemas/sitemap/0.9"
	   ,@(loop
		for doc in documents
		collect `(:url
			  :log ,(muse-url doc :with-base-url t)
			  :lastmod
			  ,(multiple-value-bind
				(second minute hour day month year dow dst-p tz)
			      (decode-universal-time
			       (file-write-date (muse-pathname doc)))
			    (declare (ignore second dow dst-p tz))
			    (format nil "~d~2,'0d~2,'0d-~2,'0d:~2,'0d"
				    year month day hour minute))
			  :changefreq "weekly"))))
	(url "/"))
    (write-html-file (eval `(with-html-output-to-string (s) ,sitemap)) url
		     :name "sitemap" :type "xml" :verbose verbose)
    ;; return how many documents are included in the sitemap
    (length sitemap)))

(defun document-is-a-blog-article-p (doc)
  (member "blog" (split-pathname (muse-pathname doc)) :test #'string=))

(defun compile-articles (&key verbose)
  "Output all the articles found in *ROOT-DIRECTORY* into *HTML-DIRECTORY*."
  (displaying-time ("rebuild main cache: ~25T~d docs ~45T in ~ds~%"
		    (length result) timing)
    (find-all-blog-articles :purge t))

  (let* ((all-documents
	  (displaying-time ("parsed ~25T~d docs ~45T in ~ds~%"
			    (length result) timing)
	    (find-muse-documents)))

	 (blog-articles-full
	  (remove-if-not #'document-is-a-blog-article-p all-documents))

	 (blog-articles-chapeau
	  (displaying-time ("parsed chapeau of ~25T~d blog articles ~45T in ~ds~%"
			    (length result) timing)
	    (find-blog-articles *blog-directory*)))

	 (conf-articles-chapeau
	  (displaying-time ("parsed chapeau of ~25T~d confs articles ~45T in ~ds~%"
			    (length result) timing)
	    (find-blog-articles *confs-directory*)))

	 (pgsql-articles-chapeau
	  (displaying-time ("parsed chapeau of ~25T~d pgsql articles ~45T in ~ds~%"
			    (length result) timing)
	    (find-muse-documents :base-directory *pgsql-directory*
                                 :parse-fn #'muse-parse-chapeau)))

	 (emacs-articles-chapeau
	  (displaying-time ("parsed chapeau of ~25T~d emacs articles ~45T in ~ds~%"
			    (length result) timing)
	    (find-muse-documents :base-directory *emacs-directory*
                                 :parse-fn #'muse-parse-chapeau))))

    (displaying-time ("compiled the home page ~45T in ~ds~%" timing)
      (compile-home-page :documents blog-articles-chapeau :verbose verbose))

    (displaying-time ("compiled the tags cloud ~45T in ~ds~%" timing)
      (compile-tags-cloud :documents blog-articles-chapeau :verbose verbose))

    (displaying-time ("compiled the blog archives page ~45T in ~ds~%" timing)
      (compile-blog-archives :documents blog-articles-chapeau :verbose verbose))

    (displaying-time ("compiled ~25T~d documents ~45T in ~ds~%" result timing)
      (compile-site-documents :documents all-documents :verbose verbose))

    (displaying-time ("compiled ~25T~d blog indexes ~45T in ~ds~%" result timing)
      (compile-blog-indexes :documents blog-articles-chapeau :verbose verbose))

    (displaying-time ("compiled confs listing ~45T in ~ds~%" timing)
      (compile-conf-index :documents conf-articles-chapeau :verbose verbose))

    (displaying-time ("compiled projects listing ~45T in ~ds~%" timing)
      (compile-projects-index :pgsql pgsql-articles-chapeau
                              :emacs emacs-articles-chapeau
                              :verbose verbose))

    (displaying-time ("compiled ~25T~d tag listings ~45T in ~ds~%" result timing)
      (compile-tags-lists :documents blog-articles-chapeau :verbose verbose))

    (displaying-time ("compiled ~25T~d rss feeds ~45T in ~ds~%" result timing)
      (compile-rss-feeds :documents blog-articles-full :verbose verbose))

    (displaying-time ("compiled the sitemap ~45T in ~ds~%" timing)
      (compile-sitemap :documents all-documents :verbose verbose))))

