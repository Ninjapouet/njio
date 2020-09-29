# sioc

sioc is a Streaming IO Combinators library. This library is likely a merge concept
between various streaming libraries, IO manipulations and Lwt stuff. It allows
reasoning with streams (mostly IO ones, but in fact, any stream works) and compose
them in a Lwt style.

As there are several existing streaming stuff implementation, sioc doesn't implement
them but allows to select which implementation you want by choosing the related
package (currently, only lwt_stream are used through sioc-lwt_stream package).
