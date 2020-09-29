(** Streamed IO operations.

    This module offers some tools to ease streamed IO transformations. Such
    kind of operations can be found in various libraries with different
    style but infortunately, I didn't find such a style that correspond to
    my own needs.

    {1 Stream parametrization}

    There are several existing implementation:
    - {!Stdlib}'s {!Stream};
    - the {!Contrainer}'s {!Iter};
    - {!Streaming};
    - {!Lwt_stream};
    and probably even more. As I didn't know what implementation would
    suits me the best, I decided to parametrize the library by a stream
    implementation represented by the interface {!STREAM}.

    {2 Lwt}

    Unlike most of stream interface except {!Lwt_stream}, we take the
    the time into account. Unerlying stream function may take time to
    execute and must not block them. Therefore, most the the {!STREAM}
    interface function must returns {!Lwt} threads. That way, callers
    can choose to let the computation run in background, wait or run it
    with a {!Lwt.join}.

    {2 Stream creation}

    Depending on the stream behavior, we must be able to construct a stream
    by pulling values from the stream or pushing values into it.

    Pulling values into a stream source allows the consumer to lead the
    stream consumption and is often more efficent. When the producer
    is asynchroneous, he mostly push values into the stream. This forces
    the stream implementation to store efficently the gathered values
    so that consumers may take them.

    The stream implementation must implement the two behavior represented
    by the two stream builder {!STREAM.pull} and {!STREAM.push}.

    {2 Stream transformations}

    We use two stream transformation operation : {!STREAM.map} and
    {!STREAM.fmap}. The first is a usual map whereas the second allows
    to filter the stream. Filtering the stream produces a sampled
    stream whose clock is therefore slower than origin stream's clock.

    There is also a sequential version of those functions to take time
    into account.

    {2 Stream consumption}

    There are two families of operations for consuming streams : iterators
    functions and folders.

    {3 Iterators}

    Iterators will simply consume stream data applying an effectful
    function on it. As we're concerned with timing, three variations
    of this operation are available : the raw one {!STREAM.iter}
    the sequential one {!STREAM.iter_s} and the parallel one
    {!STREAM.iter_p}.

    Iterators are blocking (even the raw one); be sure to handle
    them with {!Lwt} stuff.

    {3 Folders}

    Folders allow to reduce a stream into a result value in a
    functional style. They come in two version : the direct one
    {!STREAM.fold} and the sequential one {!STREAM.fold_s}.

    Like iterators, folders are blocking (even the raw one); be sure
    to handle them with {!Lwt} stuff.


*)

(** Stream interface. *)
module type STREAM = sig

  (** The stream type. *)
  type 'a t

  (** [pull f] returns a new stream using the function [f] to pull
      values into it. *)
  val pull : (unit -> 'a option) -> 'a t

  (** [pull_s f] is the same as [!pull] but where the pulling function
      [f] may take time to produce a value. Prefer using {!pull} if you
      can do it simply to avoid creating useless closures. *)
  val pull_s : (unit -> 'a option Lwt.t) -> 'a t

  (** [push ()] returns a pair [s, f] where [f] allows to push
      values into the stream [s]. *)
  val push : unit -> 'a t * ('a option -> unit)

  (** [map f s] produce a new stream where values are [f x] for
      each values of [s]. *)
  val map : ('a -> 'b) -> 'a t -> 'b t

  (** [map_s f s] is the same as {!map} with a function [f] that may
      take time to resolve. *)
  val map_s : ('a -> 'b Lwt.t) -> 'a t -> 'b t

  (** [fmap f s] is the same as {!map} but the resulting
      stream will contains only values [y] where
      [f x = Some y] for each values of [s]. *)
  val fmap : ('a -> 'b option) -> 'a t -> 'b t

  (** [fmap_s f s] is the same as {!fmap} but [f] may take time to
      resolve. *)
  val fmap_s : ('a -> 'b option Lwt.t) -> 'a t -> 'b t

  (** [next s] returns the next element of [s] (and consume it), if any. *)
  val next : 'a t -> 'a option Lwt.t

  (** [iter f s] consume all data of [s], applying the
      effectful function [f] on them. *)
  val iter : ('a -> unit) -> 'a t -> unit Lwt.t

  (** [iter_s f s] is the same as {!iter} but [f] may take time
      and all of its application is run sequentially. *)
  val iter_s : ('a -> unit Lwt.t) -> 'a t -> unit Lwt.t

  (** [iter_p f s] is them same as {!iter_s] but all
      [f] applications are run in parallel. *)
  val iter_p : ('a -> unit Lwt.t) -> 'a t -> unit Lwt.t

  (** [fold f acc s] reduce the stream [s] by applying
      [f (... (f (f acc x1) x2) ...) xn] where [x1],
      [x2], ... [xn] are the stream [s] elements. *)
  val fold : ('r -> 'a -> 'r) -> 'r -> 'a t -> 'r Lwt.t

  (** [fold_s f acc s] is the same as {!fold} but with
      a function [f] that may take time to resolve. *)
  val fold_s : ('r -> 'a -> 'r Lwt.t) -> 'r -> 'a t -> 'r Lwt.t
end

(** {1 IO}

    {2 Access control}

    Read or writing modes are type encoded into the IO type in order
    the let OCaml's typechecker ensure that streams are used soundly.

    Access modes are encoded using abstract types as boolean values. *)

(** Type encoding [true]. *)
type yes

(** Type encoding [false]. *)
type no

(** Type encoding a read only access mode. *)
type ro = yes * no

(** Type encoding a write only access mode. *)
type wo = no * yes

(** Type encoding a readable mode (either read only or read/write). *)
type 'a r = yes * 'a

(** Type encoding a writable mode (either write only or read/write). *)
type 'a w = 'a * yes

(** Type encoding read/write mode. *)
type rw = yes * yes

(** Access modes type. *)
type 'a mode =
  | RO : ro mode
  | WO : wo mode
  | RW : rw mode


class type ['a, 'b] codec = object
  method encode : 'a -> 'b
  method decode : 'b -> 'a
end

(** {2 IO interface}

*)

module type S = sig
  type ('a, 'b) t

  type 'a stream
  val pull : (unit -> 'a option) -> 'a stream
  val pull_s : (unit -> 'a option Lwt.t) -> 'a stream
  val push : unit -> 'a stream * ('a option -> unit)


  type ('a, 'b) spec =
    | I : 'a stream -> ('a, ro) spec
    | O : ('a -> unit) -> ('a, wo) spec
    | IO : 'a stream * ('a -> unit) -> ('a, rw) spec

  val make : 'a mode -> ('b, 'a) spec -> ('b, 'a) t
  val pipe : unit -> ('a, rw) t * ('a, rw) t
  val output : 'a -> ('a, _ w) t -> unit

  val next : ('a, _ r) t -> 'a option Lwt.t
  val iter : ('a -> unit) -> ('a, _ r) t -> unit Lwt.t
  val iter_s : ('a -> unit Lwt.t) -> ('a, _ r) t -> unit Lwt.t
  val iter_p : ('a -> unit Lwt.t) -> ('a, _ r) t -> unit Lwt.t

  val fold : ('a -> 'b -> 'a) -> 'a -> ('b, _ r) t -> 'a Lwt.t
  val fold_s : ('a -> 'b -> 'a Lwt.t) -> 'a -> ('b, _ r) t -> 'a Lwt.t


  val codec : ('a, 'b) codec -> ('b, 'c) t -> ('a, 'c) t
  val trap : ('a, 'b) codec -> ('b, 'c) t -> ('a, 'c) t * ('b * exn, ro) t * ('a * exn, ro) t
  val multiplex : ('a, int) codec -> int -> ('a * 'b, 'c) t * ('b, 'c) t array
end

module Make (S : STREAM) : S with type 'a stream = 'a S.t

class ['a] marshal : ?extern_flags:Marshal.extern_flags list  -> unit -> [string, 'a] codec
val id : ('a, 'a) codec
class base64 : ?pad:bool -> ?alphabet:Base64.alphabet -> unit -> [string, string] codec
