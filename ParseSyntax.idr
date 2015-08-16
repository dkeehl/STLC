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
  = ParseError ParseError
  | TyError String
  | IdentError String

instance Show SynParseError where
  show (ParseError p) = show p
  show (TyError ty) = ty ++ " is not a valid type"
  show (IdentError ident) = ident ++ " is not a valid identifier"

instance Cast ParseError SynParseError where
  cast = ParseError

SynParser : Type
SynParser = StringParser SynParseError (Ex Syn)

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

parseIdent : StringParser SynParseError String
parseIdent = pack <$> guard isValid (many1 (match isIdentChar <|> match isDigit))
  where
    isValid : List Char -> Bool
    isValid [] = False -- can't happen because of many1
    isValid (x :: _) = not (isDigit x)

parseTy : StringParser SynParseError Ty
parseTy = parseFunTy <|> parseParenTy <|> parseBaseTy
  where
    parseBaseTy : StringParser SynParseError Ty
    parseBaseTy = do
      ty <- many (match isLowercaseLetter <|> match isUppercaseLetter)
      case pack ty of
        "Num" => return Num
        "Bool" => return Bool
        ty' => failWith (TyError ty')

    parseParenTy : StringParser SynParseError Ty
    parseParenTy = do
      exactly '(' *> spaces
      parseTupleTy <|> parseSumTy <|> (parseTy <* spaces <* exactly ')')
    where
      parseTupleTy : StringParser SynParseError Ty
      parseTupleTy = (Tuple $$) . toVect <$> (sep1 (exactly ',' *> spaces) parseTy <* spaces <* exactly ')')

      parseSumTy : StringParser SynParseError Ty
      parseSumTy = (Tuple $$) . toVect <$> sep1 (spaces *> exactly '|' <* spaces) parseTy <* spaces <* exactly ')'

    parseFunTy : StringParser SynParseError Ty
    parseFunTy = do
      a <- parseBaseTy <|> parseParenTy
      let separator = spaces *> roughly "->" *> spaces
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

mutual
  parseSyn : SynParser
  parseSyn = parseApp <|> parseParenSyn <|> parseLam <|> parseNat <|> parseKeyword <|> parseVar

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
        spaces1 *> roughly "then" *> spaces1
        t <- parseSyn
        spaces1 *> roughly "else" *> spaces1
        f <- parseSyn
        let [b', t', f'] = liftExSyns [b, t, f]
        returnEx (If b' t' f')
      ident => failWith (IdentError ident)

  parseNat : SynParser
  parseNat = do
    xs <- many1 (match isDigit)
    return (E0 $ Num (cast {to = Float} (pack xs)))

  parseLam : SynParser
  parseLam = do
    exactly '\\' *> spaces
    var <- parseIdent
    spaces *> exactly ':' *> spaces
    ty <- parseTy
    exactly '.' *> spaces
    E expr <- parseSyn
    returnEx (Lam var ty expr)

  parseParenSyn : SynParser
  parseParenSyn = do
    exactly '(' *> spaces
    expr <- parseSyn
    parseTuple expr <|> parseEndParen expr
  where
    parseEndParen : Ex Syn -> SynParser
    parseEndParen expr = do
      spaces *> exactly ')'
      return expr

    parseTuple : Ex Syn -> SynParser
    parseTuple x = do
      let separator = spaces *> exactly ',' *> spaces
      E xs <- toVect <$> (separator *> sep1 separator parseSyn)
      exactly ')'
      returnEx (Tuple (liftExSyns (x :: xs)))

  parseApp : SynParser
  parseApp = do
    x <- parseArg
    E xs <- toVect <$> (spaces1 *> sep1 spaces1 parseArg)
    returnEx (foldApp (liftExSyns (x :: xs)))
  where
    parseArg : SynParser
    parseArg = parseParenSyn <|> parseLam <|> parseNat <|> parseKeyword <|> parseVar

    foldApp : Vect (S n) (Syn d) -> Syn (n + d)
    foldApp [s] = s
    foldApp {n = S n} {d = d} (s1 :: s2 :: ss) =
      rewrite plusSuccRightSucc n d in
        foldApp ((s1 :$ s2) :: map (liftSyn ltePlusOne) ss)
