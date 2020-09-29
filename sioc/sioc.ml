
(* there are several stream implementations and i want to be able to change
   if any performance issue happen *)
module type STREAM = sig
  type 'a t

  (* stream constructors either by pulling of pushing *)
  val pull : (unit -> 'a option) -> 'a t
  val pull_s : (unit -> 'a option Lwt.t) -> 'a t
  val push : unit -> 'a t * ('a option -> unit)

  (* stream filters *)
  val map : ('a -> 'b) -> 'a t -> 'b t
  val map_s : ('a -> 'b Lwt.t) -> 'a t -> 'b t
  val fmap : ('a -> 'b option) -> 'a t -> 'b t
  val fmap_s : ('a -> 'b option Lwt.t) -> 'a t -> 'b t

  (* stream consumers. Lwt values are returned to let the user
     decide if consuming is blocking or not *)
  val next : 'a t -> 'a option Lwt.t

  val iter : ('a -> unit) -> 'a t -> unit Lwt.t
  val iter_s : ('a -> unit Lwt.t) -> 'a t -> unit Lwt.t
  val iter_p : ('a -> unit Lwt.t) -> 'a t -> unit Lwt.t

  val fold : ('r -> 'a -> 'r) -> 'r -> 'a t -> 'r Lwt.t
  val fold_s : ('r -> 'a -> 'r Lwt.t) -> 'r -> 'a t -> 'r Lwt.t
end

type yes
type no

type ro = yes * no
type wo = no * yes
type 'a r = yes * 'a
type 'a w = 'a * yes
type rw = yes * yes

type 'a mode =
  | RO : ro mode
  | WO : wo mode
  | RW : rw mode

class type ['a, 'b] codec = object
  method encode : 'a -> 'b
  method decode : 'b -> 'a
end

class ['a] marshal ?(extern_flags = []) () : [string, 'a] codec = object
  method encode s =  Marshal.from_string s 0
  method decode a =  Marshal.to_string a extern_flags
end

let id : ('a, 'a) codec = object
  method encode x = x
  method decode x = x
end

class base64 : ?pad:bool -> ?alphabet:Base64.alphabet -> unit -> [string, string] codec =
  fun ?pad ?alphabet () -> object
  method encode s = Base64.encode_exn ?pad ?alphabet s
  method decode s = Base64.decode_exn ?pad ?alphabet s
end

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
  val trap :  ('a, 'b) codec -> ('b, 'c) t -> ('a, 'c) t * ('b * exn, ro) t * ('a * exn, ro) t

  val multiplex : ('a, int) codec -> int -> ('a * 'b, 'c) t * ('b, 'c) t array
end

module Make (S : STREAM) = struct
  (* various IO combinators used by helium *)

  type 'a stream = 'a S.t
  let pull = S.pull
  let pull_s = S.pull_s
  let push = S.push

  type ('a, 'm) t = {
    input : 'a stream;
    output : 'a -> unit;
  }

  type ('a, 'b) spec =
    | I : 'a stream -> ('a, ro) spec
    | O : ('a -> unit) -> ('a, wo) spec
    | IO : 'a stream * ('a -> unit) -> ('a, rw) spec

  let make : type a b. a mode -> (b, a) spec -> (b, a) t = fun m s ->
    match m, s with
    | RO, I input -> {input; output = ignore}
    | WO, O output -> {input = S.pull (fun _ -> None); output}
    | RW, IO (input, output) -> {input; output}

  let pipe : unit -> ('a, rw) t * ('a, rw) t = fun () ->
    let left_stream, push_left = S.push () in
    let right_stream, push_right = S.push () in
    let output_left a = push_right (Some a) in
    let output_right a = push_left (Some a) in
    let left = {input = left_stream; output = output_left} in
    let right = {input = right_stream; output = output_right} in
    left, right

  let output a io = io.output a

  let codec : ('a, 'b) codec -> ('b, 'c) t -> ('a, 'c) t = fun c s -> {
      input = S.map c#decode s.input;
      output = fun a -> s.output (c#encode a);
    }

  let trap : ('a, 'b) codec -> ('b, 'c) t -> ('a, 'c) t * ('b * exn, ro) t * ('a * exn, ro) t =
    fun c s ->
    let a_stream, a_push = S.push () in
    let b_stream, b_push = S.push () in
    let output a = try s.output (c#encode a) with e -> a_push (Some (a, e)) in
    let decode (b : 'b) = try Some (c#decode b) with e -> b_push (Some (b, e)); None in
    let input = S.fmap decode s.input in
    let s = {input; output} in
    s, make RO (I b_stream), make RO (I a_stream)

  let next io = S.next io.input

  let iter f io = S.iter f io.input
  let iter_s f io = S.iter_s f io.input
  let iter_p f io = S.iter_p f io.input

  let fold f a io = S.fold f a io.input
  let fold_s f a io = S.fold_s f a io.input

  let multiplex : ('a, int) codec -> int -> ('a * 'b, 'c) t * ('b, 'c) t array = fun c max ->
    let r = Array.init max (fun _ -> push ()) in
    let l, l_push = push () in
    let to_i, of_i = c#encode, c#decode in
    let output_right (a, b) =
      let i = to_i a in
      if i >= 0 && i < max then
        (snd r.(i)) (Some b)
      else
        invalid_arg "multiplex: encode" in
    let output_left i b = l_push (Some (of_i i, b)) in
    let left = {input = l; output = output_right} in
    let rights = Array.mapi (fun i (r, _) -> {input = r; output = output_left i}) r in
    left, rights


end
