
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

type ('a, 'b) codec =
  | Codec : ('a -> 'b) * ('b -> 'a) -> ('a, 'b) codec
  | Filter : ('a -> 'b option) * ('b -> 'a option) -> ('a, 'b) codec

let codec : ('a -> 'b) -> ('b -> 'a) -> ('a, 'b) codec =
  fun e d -> Codec (e, d)

let filter : ('a -> 'b option) -> ('b -> 'a option) -> ('a, 'b) codec =
  fun e d -> Filter (e, d)

let marshal ?(extern_flags = []) () =
  let encode a = Marshal.to_string a extern_flags in
  let decode s = Marshal.from_string s 0 in
  codec encode decode

let id () =
  let id x = x in
  codec id id

let base64 :
  ?pad:bool -> ?alphabet:Base64.alphabet -> unit -> (string, string) codec =
  fun ?pad ?alphabet () ->
  let encode s = Base64.encode_exn ?pad ?alphabet s in
  let decode s = Base64.decode_exn ?pad ?alphabet s in
  codec encode decode

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

  val map : ('a, 'b) codec -> ('b, 'c) t -> ('a, 'c) t
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

  let map : type a b. (a, b) codec -> (b, 'c) t -> (a, 'c) t = fun c s ->
    match c with
    | Codec (encode, decode) -> {
        input = S.map decode s.input;
        output = fun a -> s.output (encode a);
      }
    | Filter (encode, decode) ->
      let output a = match encode a with None -> () | Some v -> s.output v in {
        input = S.fmap decode s.input;
        output;
      }

  let next io = S.next io.input

  let iter f io = S.iter f io.input
  let iter_s f io = S.iter_s f io.input
  let iter_p f io = S.iter_p f io.input

  let fold f a io = S.fold f a io.input
  let fold_s f a io = S.fold_s f a io.input

  let multiplex : ('a, int) codec -> int -> ('a * 'b, 'c) t * ('b, 'c) t array =
    fun c max ->
    let l, l_push = push () in
    let r = Array.init max (fun _ -> push ()) in
    let to_i, of_i = match c with
      | Codec (to_i, of_i) -> (fun a -> Some (to_i a)), (fun i -> Some (of_i i))
      | Filter (to_i, of_i) -> to_i, of_i in
    let output_right (a, b) = match to_i a with
      | Some n when n >= 0 && n < max -> Some b |> snd r.(n)
      | _ -> () in
    let output_left i b = match of_i i with
      | Some n -> l_push (Some (n, b))
      | _ -> () in
    let multiplexed = {
      input = l;
      output = output_right;
    } in
    let rights = Array.mapi
        (fun i (r, _) -> {input = r; output = output_left i}) r in
    multiplexed, rights

end
