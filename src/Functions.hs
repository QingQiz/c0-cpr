module Functions where

import Data.Char
import Data.List
import Data.List.Split
import qualified Data.Map as Map
import qualified Data.Set as Set


untilF cnd f x = until' cnd f (f x) x where
    until' cnd f x x' = if cnd x x' then x' else until' cnd f (f x) x

untilNoChange :: Eq a => (a -> a) -> a -> a
untilNoChange = untilF (==)


conn_cmd  cmd     = ['\t':cmd]
conn_lab  lab     = [lab ++ ":"]
conn_inst cmd l r = ["\t" ++ cmd ++ "\t" ++ l ++ ", " ++ r]
conn_inst_s cmd a = ["\t" ++ cmd ++ "\t" ++ a]

cnt c = foldl (\z x -> if x == c then z + 1 else z) 0
cntElem c = foldl (\z x -> if x `elem` c then z + 1 else z) 0

inMap a m = case Map.lookup a m of
    Just _ -> True
    _ -> False

getItem a m = case Map.lookup a m of
    Just x -> x
    _      -> error $ "\n" ++ show a ++ " not in " ++ show m

elemWhere f l = case dropWhile (not . f) l of
    [] -> error $ "\nelem can not found" ++ " in " ++ show l
    x  -> head x

removeWhere f = filter (not . f)
removeItem x = removeWhere (==x)

rmDupItem l = Set.toList $ Set.fromList l

fst' (a, _, _) = a
snd' (_, b, _) = b
trd' (_, _, c) = c


splitAt3 a b l =
    let rt = splitAt b l
        r = snd rt
        m = splitAt a (fst rt)
    in  (fst m, snd m, r)

mergeInto Nothing l = l
mergeInto (Just x) l = x : l

first f x = head' $ dropWhile (not . f) x where head' (x:xs) = x

splitWithFunction code = reverse $ map reverse $ foldl step [[]] code where
    step z@(x:xs) c = if head c `notElem` ".\t" then [c] : z else (c:x):xs

----------------------------------------------------------------
--                functions for registers                     --
----------------------------------------------------------------
isReg :: String -> Bool
isReg c = '%' `elem` c
isNotReg = not . isReg

isConst c = let c' = dropWhile (`elem` "$-") c in c' /= "" && all isDigit c'

isRegGroup c = let c' = dropWhile (`elem` "+-*/") c in
    cntElem "()" c' == 2 && cntElem "+-*/~" c' == 0
isNotRegGroup = not . isRegGroup

isSimple c = isNotRegGroup c && isNotArith c
isNotSimple = not . isSimple

getGroupVal = init . concatMap (splitOn ")") . concatMap (splitOn "(") . splitOn ","


getRegs x = if not (isReg x) then [] else
    if isRegGroup x
    then let (_:vals) = getGroupVal x in
         (:) x $ concatMap getRegs vals
    else if isSimple x
        then [x]
        else let (a, b, op) = getOperand x in
            getRegs a ++ getRegs b


getOperand c =
    let h = takeWhile (`elem` "+-*/~$") c
        c' = drop (length h) c
    in case break (`elem` "+-*/~") c' of
        (a, "") -> (h ++ a, "", "")
        (a, b ) -> (h ++ a, tail b, [head b])


getRegIndex :: String -> String
getRegIndex = reverse . takeWhile isDigit . reverse


rmRegIndex r
    | not (isReg r) = r
    | isRegGroup r =
          let (h:vals) = getGroupVal r
          in  h ++ "(" ++ intercalate "," (map rmRegIndex vals) ++ ")"
    | isSimple r = reverse $ dropWhile isDigit $ reverse r
    | otherwise =
          let (a, b, op) =  getOperand r
          in  rmRegIndex a ++ op ++ rmRegIndex b

isArith r = case getOperand r of
    (a, "", "") -> False
    _           -> True
isNotArith = not . isArith

isCommd c c' = ("\t" ++ c) `isPrefixOf` c' || c `isPrefixOf` c'

getCommd = head . tail . splitOn "\t"
getCommdTarget = last . splitOn "\t"

fixAddr r = if head r == '*' then tail r else r
