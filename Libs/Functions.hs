module Functions where

import Data.Char
import Data.List
import Data.List.Split
import qualified Data.Map as Map
import qualified Data.Set as Set


untilNoChange :: Eq a => (a -> a) -> a -> a
untilNoChange f x = until_no_change' f (f x) x where
    until_no_change' f x x' = if x == x' then x else until_no_change' f (f x) x


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

elemWhere f l = case snd $ break f l of
    [] -> error $ "\nelem can not found" ++ " in " ++ show l
    x  -> head x

removeWhere f l = filter (not . f) l
removeItem x l = removeWhere (==x) l

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

----------------------------------------------------------------
--                functions for registers                     --
----------------------------------------------------------------
isReg c = '%' `elem` c

isConst c = let c' = dropWhile (`elem` "$-") c in c' /= "" && all isDigit c'

isRegGroup c = let c' = dropWhile (`elem` "+-*/") c in
    cntElem "()" c' == 2 && cntElem "+-*/~" c' == 0


isSimple c = not (isRegGroup c) && case getOperand c of
    (a, "", "") -> True
    _           -> False


getGroupVal = init . concat . map (splitOn ")") . concat . map (splitOn "(") . splitOn ","


getRegs x = if not (isReg x) then [] else
    if isRegGroup x
    then let (_:vals) = getGroupVal x in
         (:) x $ concat $ map getRegs vals
    else if isSimple x
        then [x]
        else let (a, b, op) = getOperand x in
            getRegs a ++ getRegs b


getOperand c =
    let h = takeWhile (\x -> x `elem` "+-*/~$") c
        c' = drop (length h) c
    in case break (\x -> x `elem` "+-*/~") c' of
        (a, "") -> (h ++ a, "", "")
        (a, b ) -> (h ++ a, tail b, head b : [])


getRegIndex :: String -> String
getRegIndex = reverse . takeWhile isDigit . reverse


rmRegIndex r = if not (isReg r) then r else
    if isRegGroup r
    then let (h:vals) = getGroupVal r in
        h ++ "(" ++ intercalate "," (map rmRegIndex vals) ++ ")"
    else if isSimple r
        then reverse $ dropWhile isDigit $ reverse r
        else let (a, b, op) =  getOperand r in
            rmRegIndex a ++ op ++ rmRegIndex b
