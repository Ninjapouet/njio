open Sioc_lwt_stream

let _ = Lwt_main.run begin

    let print = Fmt.pr "%i@." in

    (* make ro  *)
    let s = make RO (I (Lwt_stream.of_list [1; 2; 3])) in
    iter print s;%lwt

    (* make wo *)
    let s = make WO (O print) in
    output 1234 s;

    (* make rw *)
    let s = make RW (IO (Lwt_stream.of_list [4; 5; 6], print)) in
    iter print s;%lwt
    output 4321 s;

    (* pipes *)
    let l, r = pipe () in
    Lwt.async (fun () -> iter print r);
    Lwt.async (fun () -> iter print l);
    output 42 l;
    output 24 r;

    (* fold *)
    let%lwt res = fold (+) 0 (make RO (I (Lwt_stream.of_list [4; 2; 6]))) in
    print res;

    (* codec *)
    let c = object
      method encode = int_of_string
      method decode = string_of_int
    end in
    let s = codec c (make RO (I (Lwt_stream.of_list [4; 2; 6]))) in
    iter (Fmt.pr "\"%s\"@.") s;%lwt


    (* trap *)
    let c = object
      method encode = string_of_int
      method decode = int_of_string
    end in
    let stream, write = push () in
    let s, str, _ = trap c (make RO (I stream)) in
    Lwt.async (fun () -> iter print s);
    Lwt.async (fun () -> iter (fun (s, e) -> Fmt.pr "error: \"%s\" %a@." s Fmt.exn e) str);
    write (Some "45");
    write (Some "foo");
    write (Some "76");


    (* multiplex *)
    let l, r = multiplex Sioc.id 3 in
    Array.iteri (fun i io -> Lwt.async (fun () -> iter (Fmt.pr "channel %i: %i@." i) io)) r;
    Lwt.async (fun () -> iter (fun (a, b) -> Fmt.pr "mux (%i, %i)@." a b) l);
    output (2, 42) l;
    output 32 r.(0);
    output (1, 17) l;
    output 23 r.(1);

    Lwt.return_unit

  end
