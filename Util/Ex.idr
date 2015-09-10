module Ex

%default total

infixr 0 $$

||| Lightweight syntax for dependent pairs whose first value can usually be inferred:
||| Ex b <=> (x : _ ** b _)
||| E y <=> (_ ** y)
||| (could probably be a syntax definition instead?)
data Ex : (a -> Type) -> Type where
  E : b x -> Ex b

fst : Ex {a = a} b -> a
fst (E {x = x} _) = x

snd : (ex : Ex b) -> b (fst ex)
snd (E y) = y

map : ({x : a} -> b x -> c) -> Ex b -> c
map f (E x) = f x

(<$>) : ({x : a} -> b x -> c) -> Ex b -> c
(<$>) = map

-- there's a weird error sometimes with map and <$>
($$) : ({x : a} -> b x -> c) -> Ex b -> c
($$) = map
