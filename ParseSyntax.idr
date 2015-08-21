module ParseSyntax

import Data.Vect

import Parser
import PiVect
import Syntax
import Ty

import Util.Ex
import Util.LTE
import Util.Sigma
import Util.Vect

%default total

data SynParseError
  = ParseError String
  | TyError String
  | IdentError String

instance Show SynParseError where
  show (ParseError p) = show p
  show (TyError ty) = ty ++ " is not a valid type"
  show (IdentError ident) = ident ++ " is not a valid identifier"

instance ParseError SynParseError where
  fromString = ParseError

Parser' : Type -> Type
Parser' = Parser SynParseError String Char

SynParser : Type
SynParser = Parser' (Ex Syn)

TyParser : Type
TyParser = Parser' Ty

isLowercaseLetter : Char -> Bool
isLowercaseLetter c = 'a' <= c && c <= 'z'

isUppercaseLetter : Char -> Bool
isUppercaseLetter c = 'A' <= c && c <= 'Z'

isIdentChar : Char -> Bool
isIdentChar c =
  isLowercaseLetter c ||
  isUppercaseLetter c ||
  (elem c (unpack "+=<>_!@#$%^&*-|'\"?/`~"))

keywords : List String
keywords =
  [ "if"
  , "then"
  , "else"
  , "def"
  ]


%default partial

parseIdent : Parser' String
parseIdent = pack <$> guard isValid (many1 (match isIdentChar <|> match isDigit))
  where
    isValid : List Char -> Bool
    isValid [] = False -- can't happen because of many1
    isValid (x :: _) = not (isDigit x)

parseTy : TyParser
parseTy = parseFunTy <|> parseParenTy <|> parseBaseTy
  where
    parseBaseTy : TyParser
    parseBaseTy = do
      ty <- many (match isLowercaseLetter <|> match isUppercaseLetter)
      case pack ty of
        "Num" => return Num
        "Bool" => return Bool
        ty' => failWith (TyError ty')

    parseParenTy : TyParser
    parseParenTy = do
      token '(' *> spaces
      parseTupleTy <|> parseSumTy <|> (parseTy <* spaces <* token ')')
    where
      parseTupleTy : TyParser
      parseTupleTy = do
        -- Tuple . toVect <$> (sep1 (token ',' *> spaces) parseTy <* spaces <* token ')')
        xs <- sep1 (spaces *> token ',' *> spaces) parseTy <* spaces <* token ')'
        return (Tuple (toVect xs))

      parseSumTy : TyParser
      parseSumTy = do
        xs <- sep1 (spaces *> token '|' *> spaces) parseTy <* spaces <* token ')'
        return (Sum (toVect xs))

    parseFunTy : TyParser
    parseFunTy = do
      a <- parseBaseTy <|> parseParenTy
      let separator = spaces *> string "->" *> spaces
      as <- separator *> sep1 separator parseTy
      return (foldl (:->) a as)

liftSyn : (m `LTE` n) -> Syn m -> Syn n
liftSyn p (Var v) = Var v
liftSyn p (Num x) = Num x
liftSyn p (Bool x) = Bool x
liftSyn (LTESucc p) (Lam v ty s) = Lam v ty (liftSyn p s)
liftSyn (LTESucc p) (sx :$ sy) = liftSyn p sx :$ liftSyn p sy
liftSyn (LTESucc p) (If sb st sf) = If (liftSyn p sb) (liftSyn p st) (liftSyn p sf)
liftSyn (LTESucc p) (Tuple ss) = Tuple (map (liftSyn p) ss)
liftSyn (LTESucc p) (Variant ety s) = Variant ety (liftSyn p s)

liftSyns : {ds : Vect n Nat} -> (ss : PiVect Syn ds) -> Vect n (Syn (fst (upperBound ds)))
liftSyns {ds = ds} ss = zipWithToVect liftSyn (snd (upperBound ds)) ss

liftExSyns : (ss : Vect n (Ex Syn)) -> Vect n (Syn (fst (upperBound (map fst ss))))
liftExSyns ss = liftSyns (unzip ss)

E0 : b Z -> Ex b
E0 = E

parseNat : Parser' Nat
parseNat = do
  xs <- many1 (match isDigit)
  return (cast {to = Nat} $ cast {to = Int} $ pack xs)

parseFloat : Parser' Float
parseFloat = do
  xs <- many1 (match isDigit)
  return (cast {to = Float} $ pack xs)

mutual
  parseSyn : SynParser
  parseSyn = choice [parseAs, parseVariant, parseApp, parseParenSyn, parseLam, parseNum, parseKeyword, parseVar]

  parseVar : SynParser
  parseVar = E0 . Var <$> guard (\ident => not (elem ident keywords)) parseIdent

  parseKeyword : SynParser
  parseKeyword =
    case !parseIdent of
      "true" => return (E0 $ Bool True)
      "false" => return (E0 $ Bool False)
      "if" => do
        spaces
        b <- parseSyn
        spaces1 *> string "then" *> spaces1
        t <- parseSyn
        spaces1 *> string "else" *> spaces1
        f <- parseSyn
        let [b', t', f'] = liftExSyns [b, t, f]
        return (E $ If b' t' f')
      ident => failWith (IdentError ident)

  parseAs : SynParser
  parseAs = do
    E t <- choice [parseVariant, parseApp, parseParenSyn, parseLam, parseNum, parseKeyword, parseVar]
    spaces *> token ':' *> spaces
    ty <- parseTy
    return (E $ t `As` ty)

  parseNum : SynParser
  parseNum = do
    x <- parseFloat
    return (E0 $ Num x)

  parseLam : SynParser
  parseLam = do
    token '\\' *> spaces
    var <- parseIdent
    spaces *> token ':' *> spaces
    ty <- parseTy
    token '.' *> spaces
    E expr <- parseSyn
    return (E $ Lam var ty expr)

  parseVariant : SynParser
  parseVariant = do
    string "variant" *> spaces1
    i <- parseNat
    spaces1
    E s <- choice [parseVariant, parseApp, parseParenSyn, parseLam, parseNum, parseKeyword, parseVar]
    return (E $ Variant i s)

  parseParenSyn : SynParser
  parseParenSyn = do
    token '(' *> spaces
    expr <- parseSyn
    parseTuple expr <|> parseEndParen expr
  where
    parseEndParen : Ex Syn -> SynParser
    parseEndParen expr = do
      spaces *> token ')'
      return expr

    parseTuple : Ex Syn -> SynParser
    parseTuple x = do
      let separator = spaces *> token ',' *> spaces
      xs <- separator *> sep1 separator parseSyn
      token ')'
      return (E $ Tuple (liftExSyns (x :: toVect xs)))

  parseApp : SynParser
  parseApp = do
    x <- parseArg
    xs <- spaces1 *> sep1 spaces1 parseArg
    return (E $ foldApp (liftExSyns (x :: toVect xs)))
  where
    parseArg : SynParser
    parseArg = choice [parseVariant, parseParenSyn, parseLam, parseNum, parseKeyword, parseVar]

    foldApp : Vect (S n) (Syn d) -> Syn (n + d)
    foldApp [s] = s
    foldApp {n = S n} {d = d} (s1 :: s2 :: ss) =
      rewrite plusSuccRightSucc n d in
        foldApp ((s1 :$ s2) :: map (liftSyn ltePlusOne) ss)
