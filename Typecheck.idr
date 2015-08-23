module Typecheck

import Data.Fin
import Data.Vect

import PiVect
import Syntax
import Term
import Ty

import Util.Dec
import Util.Elem
import Util.Ex
import Util.Sigma

%default total

data TypeError
  = App
  | If
  | Variant
  | LamRec
  | As (Scoped d gv) Ty Ty
  | Fix
  | CantInfer

typecheck :
  {gv : Vect n String} ->
  (gty : Vect n Ty) ->
  (s : Scoped d gv) ->
  Either TypeError (Ex (Term d gty))

typecheck gty (Var {v = v} p) =
  return (E $ Var v (iso p gty))

typecheck gty (Num n) =
  return (E $ Num n)

typecheck gty (Bool b) =
  return (E $ Bool b)

typecheck gty (LamRec {vf = vf} {v = v} a b sc) with (typecheck ((a :-> b) :: a :: gty) sc)
  typecheck gty (LamRec {vf = vf} {v = v} a b sc) | Right (E {x = b'} tm) with (b =? b')
    typecheck gty (LamRec {vf = vf} {v = v} a b sc) | Right (E {x = b} tm) | Yes Refl = Right (E $ LamRec vf v tm)
    typecheck gty (LamRec {vf = vf} {v = v} a b sc) | Right (E {x = b'} tm) | No _ = Left LamRec
  typecheck gty (LamRec {vf = vf} {v = v} a b sc) | Left err = Left LamRec

typecheck gty (Lam {v = v} a sc) = do
  E tm <- typecheck (a :: gty) sc
  return (E $ Lam v tm)

typecheck gty (scx :$ scy) with (typecheck gty scx, typecheck gty scy)
  typecheck _ _ | (Right (E {x = a :-> b} tmx), Right (E {x = c} tmy)) with (a =? c)
    typecheck _ _ | (Right (E tmx), Right (E tmy)) | Yes Refl = Right (E (tmx :$ tmy))
    typecheck _ _ | _ | No _ = Left App
  typecheck _ _ | _ = Left App

typecheck gty (If scx scy scz) with (typecheck gty scx, typecheck gty scy, typecheck gty scz)
  typecheck _ _ | (Right (E {x = Bool} tmx), Right (E {x = a} tmy), Right (E {x = b} tmz)) with (a =? b)
    typecheck _ _ | (Right (E tmx), Right (E tmy), Right (E tmz)) | Yes Refl = Right (E $ If tmx tmy tmz)
    typecheck _ _ | _ | No _ = Left If
  typecheck _ _ | _ = Left If

typecheck gty (Tuple scs) = do
  tms <- sequence (map (typecheck gty) scs)
  return (E $ Tuple (unzip tms))

typecheck gty (Variant i s) =
  Left Variant -- has to be wrapped in an As

-- also: typecheck gty (s `As` Sum tys) for inference!
typecheck gty (Variant i s `As` Sum {n = n} tys) with (typecheck gty s, natToFin i n)
  typecheck _ (Variant i s `As` Sum {n = n} tys) | (Right (E {x = ty} tm), Just i') with (ty =? index i' tys)
    typecheck _ (Variant i s `As` Sum {n = n} tys) | (Right (E tm), Just i') | Yes Refl =
      Right (E $ Variant (fromFin i' tys) tm)
    typecheck _ (Variant i s `As` Sum {n = n} tys) | (Right (E tm), Just i') | No _ = Left Variant
  typecheck _ _ | _ = Left Variant

typecheck gty (s `As` ty) = do
  E {x = ty'} tm <- typecheck gty s
  case ty =? ty' of
    Yes _ => Right (E tm)
    No _ => Left (As s ty ty')

typecheck gty (Let {v = v} s t) = do
  E {x = a} s' <- typecheck gty s
  E {x = b} t' <- typecheck (a :: gty) t
  return (E (Lam v t' :$ s'))
  -- return (E (Lam v t' :$ s'))
