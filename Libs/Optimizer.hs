module Optimizer where

import Debug.Trace

import TAC
import CFG
import Livness
import Functions
import Data.Char
import Data.List
import Data.List.Utils
import qualified Data.Map as Map


optimize code = untilNoChange (doGlobalOptimize . buildCFG) code

-- doLocalOptimize :: CFG -> CFG
doGlobalOptimize cfg =
    let
        (ids, bbs_org) = unzip $ Map.toList $ getBasicBlocks cfg
        fs = splitWithFunction bbs_org
    in
        (++) (getHeader cfg) $ concat $ map globalOptimizeOnAFunction fs
    where
        splitWithFunction bbs = foldr step [] bbs where
            step b z@(x:xs) = case getEntry b of
                [] -> [b]:z
                _  -> (b:x):xs
            step b [] = [[b]]


show' ((a, b):ts) = "\n" ++ (if length a >= 8 then a ++ "" else a ++ "\t") ++ "\t" ++ (if null b then "" else "=\t" ++ b) ++ show' ts
show' [] = "\n"
globalOptimizeOnAFunction bbs =
    let
        tacs          = map (toTAC . getCode) bbs
        ids           = map getId bbs
        entries       = map getEntry bbs
        optimized_tac = untilNoChange (\x -> optimizeOnce x ids entries) tacs

    in
        -- error $ (show' (concat tacs) ++ "\n\n" ++ show' (concat optimized_tac))
        -- error $ show tacs
        fromTAC optimized_tac ids entries
    where
        optimizeOnce tacs ids entries =
            let dead_code = globalDeadCodeElim tacs ids entries
                expr_elim = map (\x -> fst' $ commonSubexprElim x Map.empty Map.empty) dead_code
                copy_prop = globalConstCopyPropagation expr_elim ids entries
            in  trace (show' $ concat copy_prop) copy_prop


globalDeadCodeElim tacs ids entries = untilNoChange (\x -> globalDeadCodeElimOnce x ids entries) tacs

globalDeadCodeElimOnce [] _ _ = []
globalDeadCodeElimOnce tacs ids entries =
    let
        liv_final = livnessAnalysis tacs ids entries
    in
        (\id -> let tac = getItem id id_tac
                    liv = tail $ collectLivness tac (getItem id liv_final)
                in  doElimination tac liv) `map` ids
    where
        id_tac = Map.fromList $ zip ids tacs
        doElimination tac liv = elim tac liv where
            elim (x@(a, b):tr) (l:lr)
                | isReg a = if isLiv a l then x : (elim tr lr) else elim tr lr
                | a == "cltd" || a == "cltq" || a == "cqto" = if isLiv' "%rax" l then x : (elim tr lr) else elim tr lr
                | "set" `isPrefixOf` a = if isLiv b l then x : (elim tr lr) else elim tr lr
                | otherwise = x : (elim tr lr)
            elim _ _ = []

        isLiv r liv  = let fixed_r = rmRegIndex r in
            r `elem` liv || fixed_r `elem` liv
        isLiv' r liv = r `elem` (map rmRegIndex liv)


globalConstCopyPropagation [] _ _ = []
globalConstCopyPropagation tacs ids entries =
    let
    in
        snd $ unzip $ Map.toList $ foldr forABlock (Map.fromList $ zip ids tacs) ids
    where
        ud = "ud" -- undefiend
        nc = "nc" -- not const
        id_entry = zip ids entries

        findConst tac = Map.toList $ Map.fromList -- find the last assign
            $ map (\(a, b) -> (rmRegIndex a, b)) $ sort
            -- find all (rbp, const)
            $ filter (\(a, b) -> "rbp" `isInfixOf` a) $ filter (isConst . snd) tac

        forABlock id id_tac =
            let consts = findConst (getItem id id_tac)
            in  foldr (forAConst id) id_tac consts

        -- forAConst :: (lst, rst) -> id_tac -> id_tac'
        forAConst id_start (a, b) id_tac =
            let stat_init = Map.fromList
                    $ map (\x@(id, _) -> (,) id (ud, buildStat ud x))
                    $ Map.toList id_tac
                stat = untilNoChange updateStat stat_init
            in  doReplace (a, b) stat id_tac
            where
                doReplace (a, b) id_stat id_tac = Map.fromList $ map doReplace' (Map.toList id_tac) where
                    doReplace' (id, tac)
                        | bef == ud || bef == nc = (id, tac)
                        | otherwise = (id, func a bef tac)
                        where (bef, aft) = getItem id id_stat
                              func a b ((l, r):tac)
                                  | rmRegIndex a == rmRegIndex l = tac
                                  | otherwise = (replace a b l, replace a b r) : func a b tac
                              func _ _ _ = []

                buildStat init (id, tac)
                    | id == id_start = meet init b
                    | otherwise =
                          let const = findConst tac
                              l     = filter (\(ca, cb) -> ca == a) const
                              b'    = if null l then ud else snd $ head l
                          in meet init b'

                updateStat id_stat = Map.fromList $ map (\id -> (,) id $ updateStat' id) ids where
                    updateStat' id =
                        let fs = map fst $ filter (\(i, e) -> id `elem` e) id_entry
                            st = map (\id -> snd $ getItem id id_stat) fs
                            (bef, aft) = getItem id id_stat
                            bef' = foldr (\x z -> meet x z) bef st
                            aft' = buildStat bef' (id, getItem id id_tac)
                        in  (bef', aft')

        meet a b | a == nc || b == nc = nc
                 | a == ud = b
                 | b == ud = a
                 | a /= b  = nc
                 | a == b  = a


commonSubexprElim [] _ _ = ([], Map.empty, Map.empty)
commonSubexprElim tac init_z init_eq = untilNoChange convert (tac, Map.empty, Map.empty) where
    convert (tac, _, _) = csElim tac [] init_z init_eq

    csElim (c:cs) code z eq =
        csElim cs (doReplace c z eq : code) (updateZ c z) (updateEQ c eq)
    csElim [] code z eq = (constFolding $ reverse code, z, eq)

    isArith r = case getOperand r of
        (a, "", "") -> False
        _           -> True
    isNotArith = not . isArith

    updateZ c z =
        if snd c == "" || isLetter (head $ fst c) || '%' `notElem` (snd c)
        then z
        else if isArith $ snd c then Map.insert (snd c) (fst c) z else z

    updateEQ c@(a, b) z
        | b == "" || '%' `notElem` a || "%rbp" `isPrefixOf` a = z
        | isNotArith b = let res = Map.insert a b z
                         in  if "rip" `isInfixOf` b && head b /= '*'
                             then Map.insert ("*(" ++ a ++ ")0") ('*':b) res
                             else res
        | otherwise = z

    doReplace x@(_, "") _ _ = x
    doReplace c z eq =
        -- common subexpression elimination
        case Map.lookup (snd c) z of
            Nothing -> if isRegGroup (snd c) && head (snd c) == '*'
                then case Map.lookup (tail (snd c)) z of
                    -- copy propagation
                    Nothing -> (fst c, doCopy (snd c) eq False)
                    Just  x -> (fst c, "*" ++ x)
                -- copy propagation
                else (fst c, doCopy (snd c) eq False)
            Just  x -> (fst c, x)


doCopy c eq ignoreIdx = case getOperand c of
    (a, "", _) -> case copy a eq of
        Nothing -> if isRegGroup a
            then let (h:val) = getGroupVal a in h ++ copyIntoG val [] ++ (tail $ snd $ break (==')') a)
            else a
        Just  x -> x
    (a, b, op) -> doCopy a eq ignoreIdx ++ op ++ doCopy b eq ignoreIdx
    where
        copyIntoG (c:cs) z = case copy c eq of
            Nothing -> copyIntoG cs (c:z)
            Just  x -> if isRegGroup x then copyIntoG cs (c:z) else copyIntoG cs (x:z)
        copyIntoG [] z = "(" ++ intercalate "," (reverse z) ++ ")"

        copy a eq = let a' = if ignoreIdx then rmRegIndex a else a in
            if a' == "" || "%rsp" `isPrefixOf` a'
            then Nothing
            else case Map.lookup a' eq of
                Nothing -> if head a' == '*'
                    then case Map.lookup (tail a') eq of
                        Nothing -> Nothing
                        Just  x -> Just $ '*':x
                    else Nothing
                Just  x -> Just x


constFolding tac = untilNoChange foldOnce tac where
    foldOnce tac =
        let bk = break (\x -> 2 == (cnt '$' $ snd x )) tac
            (h, (a, b):r) = bk -- this won't be evaluated when (snd bk) is empty
            (x, y, op) = getOperand (replace "$" "" b)
            (x', y') = (read x :: Int, read y :: Int)
            res x = (++) h $ (a, '$' : show x) : r
            resj x l = if x then (++) h $ ("jmp", l) : (tail r) else h ++ (tail r)
        in if null $ snd bk then tac else case op of
            "+" -> res $ x' + y'
            "-" -> res $ x' - y'
            "*" -> res $ x' * y'
            "/" -> res $ x' `div` y'
            "~" -> let (j, l) = head r in case j of
                "je"  -> (x' == y') `resj` l
                "jne" -> (x' /= y') `resj` l
                "jg"  -> (x' >  y') `resj` l
                "jl"  -> (x' <  y') `resj` l
                "jge" -> (x' >= y') `resj` l
                "jle" -> (x' <= y') `resj` l
                "jmp" -> True       `resj` l
                _ -> error $ show (j, l)
