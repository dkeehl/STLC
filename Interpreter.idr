module Interpreter

import Control.Catchable
import Control.Monad.State
import Data.HVect
import Data.Vect
import Data.Vect.Quantifiers

import Parser
import ParseSyntax
import Partial
import Primitives
import Scopecheck
import Show
import Syntax
import Term
import Ty
import Typecheck

import Util.All
import Util.Catcher
import Util.Either
import Util.Elem
import Util.Ex
import Util.Monad

%default partial

Env : Type
Env = Ex $ \n => (Vect n String, Ex (All {n = n} (SynVal [])))

covering nilEnv : Env
nilEnv = E ([], E [])

covering nilCons : String -> SynVal [] a -> Env -> Env
nilCons x t (E (xs, E ts)) = E (x :: xs, E (t :: ts))

covering interpretSyn :
  (Monad m, Catchable m String, Catchable m TypeError) =>
  Env ->
  Syn d ->
  m (Ex (SynVal []))
interpretSyn (E (names, E {x = as} vals)) t = do
  t' <- scopecheck (names ++ primitiveNames) t
  E t'' <- typecheck (as ++ primitiveTys) t'
  return $ E $ impatience $ eval [] (map fromSynTy id (vals ++ primitiveVals)) t''

covering interpret :
  (MonadState Env m, Catchable m String, Catchable m TypeError, Monad m) =>
  List (String, Ex Syn) ->
  m (Ex (SynVal []))
interpret [] = return $ E {x = UNIT} $ []
interpret ((name, E t) :: ts) = do
  x <- get
  E t' <- interpretSyn x t
  modify $ nilCons name t'
  interpret ts

covering interpretEnv :
  (MonadState Env m, Catchable m String, Catchable m TypeError, Monad m) =>
  List (String, Ex Syn) ->
  m Env
interpretEnv ts = interpret ts >> get

[monadStateT] (MonadTrans t, Monad m, Monad (t m), MonadState s m) => MonadState s (t m) where
  get = lift get
  put = lift . put

Errors : Vect 2 Type
Errors = [String, TypeError]

Interpreter : Type -> Type
Interpreter = CatcherT Errors $ StateT Env Identity

covering runInterpreter : Env -> Interpreter a -> (Catcher Errors a, Env)
runInterpreter env = runIdentity . flip runStateT env . runCatcherT

covering execInterpreter : Env -> Interpreter a -> Catcher Errors a
execInterpreter env = fst . runInterpreter env

covering interpretSrc : String -> Interpreter String
interpretSrc src = do
  defs <- execParser (sep1 spaces1 parseDef) src
  showExVal <$> the (Interpreter (Ex (SynVal []))) (interpret @{monadStateT} defs)
