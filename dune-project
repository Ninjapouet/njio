(lang dune 2.7)

(cram enable)

(allow_approximate_merlin)

(name sioc)

(generate_opam_files true)

(version 0.2.0)

(source (github Ninjapouet/sioc))

(bug_reports "https://github.com/Ninjapouet/sioc/issues")

(package
 (name sioc)
 (synopsis "Streaming IO combinators definitions")
 (depends
  (ocaml (>= 4.08.1))
  (fmt (>= 0.8.8))
  (base64 (>= 3.4.0))
  (lwt (>= 5.3.0))
 )
 (tags ("io", "combinators", "stream"))
 (license "Apache 2.0")
 (authors "Julien Blond <julien.blond@gmail.com>")
 (maintainers "Julien Blond <julien.blond@gmail.com>")
)

(package
 (name sioc-lwt_stream)
 (synopsis "Lwt_stream implementation of sioc combinators")
 (depends
  (sioc (= 0.2.0))
 )
 (tags ("io", "combinators", "stream", "lwt"))
 (license "Apache 2.0")
 (authors "Julien Blond <julien.blond@gmail.com>")
 (maintainers "Julien Blond <julien.blond@gmail.com>")
)
