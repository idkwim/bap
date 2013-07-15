open Ast
open Type
open Utils_common

let usage = "Usage: "^Sys.argv.(0)^" <binary> [function list]\n\
             Test program to resolve indirect jumps"

let arg = ref 0;;
let binname = ref None;;
let fnames = ref None;;
let timeout = ref 30;;
let total = ref 0;;
let succ = ref 0;;
let recoverf = ref Asmir_disasm.vsa_at

let speclist =
  ("-vsa", Arg.Unit (fun () -> recoverf := Asmir_disasm.vsa_at),
   "Use VSA based CFG recovery (default).")
  :: ("-rdescent", Arg.Unit (fun () -> recoverf := Asmir_disasm.recursive_descent_at),
      "Use recursive descent based CFG recovery.")
  :: ("-timeout", Arg.Set_int timeout,
      "<seconds> Set the per-functiom timeout.")
  :: []

let anon x =
  (match !arg, !fnames with
  | 0, _ -> binname := Some x
  | _, None -> fnames := Some [x]
  | _, Some l -> fnames := Some (x::l));
  incr arg;;

let () = Arg.parse speclist anon usage;;

if !arg < 1 then
  (Arg.usage speclist usage;
   exit 1);;

Tunegc.set_gc ();;

let asmp = Asmir.open_program (BatOption.get !binname);;

let funcs = Func_boundary.get_function_ranges asmp;;

let lift_func (n,s,e) =
  let go = match !fnames with
    | Some l when List.mem n l -> true
    | Some _ -> false
    | None -> true
  in
  if go then (
    Printf.printf "Lifting %s\n" n;
    incr total;
    flush stdout;
    let cfg = !recoverf asmp s in
    let cfg = Hacks.ast_remove_indirect cfg in
    let cfg = Ast_cond_simplify.simplifycond_cfg cfg in
    Cfg_pp.AstStmtsDot.output_graph (open_out ("resolve"^n^".dot")) cfg;
    Cfg_pp.SsaStmtsDot.output_graph (open_out ("resolvessa"^n^".dot")) (Cfg_ssa.of_astcfg cfg);
    let pp = new Pp.pp_oc (open_out ("resolve"^n^".il")) in
    pp#ast_program (Cfg_ast.to_prog cfg);
    pp#close;
    incr succ
  )
let lift_func =
  Util.timeout ~secs:!timeout ~f:lift_func
let lift_func ((n,_,_) as x) =
  try lift_func ~x
  with e ->
    Printf.printf "Lifting %s failed: %s\n" n (Printexc.to_string e)

let funcs = List.iter lift_func funcs;;

Printf.printf "%d out of %d functions recovered (%.2f%%)\n" !succ !total (((float_of_int !succ) *. 100.0) /. (float_of_int !total));;

