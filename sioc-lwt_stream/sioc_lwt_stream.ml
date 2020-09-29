open Sioc

(* stream implementation using Lwt_stream *)
module Stream = struct
  open Lwt_stream
  type 'a t = 'a Lwt_stream.t
  let pull = from_direct
  let pull_s = from
  let push = create
  let next = get
  let iter = iter
  let iter_s = iter_s
  let iter_p = iter_p
  let map = map
  let map_s = map_s
  let fmap = filter_map
  let fmap_s = filter_map_s
  let fold f s t = fold (fun a r -> f r a) t s
  let fold_s f s t = fold_s (fun a r -> f r a) t s
end

include Make(Stream)
