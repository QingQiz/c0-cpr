module CodeGen where

import Ast
import Symbol
import CGTest
import Register

import Data.List
import qualified Data.Map as Map


cProgram :: Ast -> [[String]]
cProgram (Program _ vds fds) = bind (cGlobalVarDef vds) (cFuncDefs fds)
    where bind (a, b) c = [a, c b]


cGlobalVarDef :: [Ast] -> ([String], RegTable)
cGlobalVarDef defs = foldr step ([], empty_rgt) defs where
    step (VarDef t xs) (l, rgt) =
        let
            rst = case t of
                TInt  -> foldr (step' 4) ([], empty_rgt) xs
                TChar -> foldr (step' 1) ([], empty_rgt) xs
        in
            (fst rst ++ l, Map.union (snd rst) rgt)

    step' s (Identifier i) (l, rgt) =
        (("\t.comm\t" ++ i ++ "," ++ show s) : l, Map.insert i (i ++ "(%rip)" , s) rgt)
    step' s (Array (Identifier i) (Number n)) (l, rgt) =
        (("\t.comm\t" ++ i ++ "," ++ show (n * s)) : l, Map.insert i (i ++ "(%rip)", s) rgt)


cFuncDefs :: [Ast] -> RegTable -> [String]
cFuncDefs fds rgt = concat $ foldr (\fd zero -> cAFuncDef fd rgt : zero) [] fds


cAFuncDef :: Ast -> RegTable -> [String]
cAFuncDef (FuncDef ft (Identifier fn) pl fb) rgt =
    [fn ++ ":", "\tpushq\t%rbp", "\tmovq\t%rsp, %rbp"]
        ++ bind (cParams pl) (cComdStmt fb)
        ++ ["\tpopq\t%rbp", "\tret"]
    where
        bind :: ([a], RegTable) -> (RegTable -> [a]) -> [a]
        bind (a, b) c = (++) a $ c $ Map.union b rgt

        cParams pls = (for_pl pls, Map.fromList $ get_param_reg pls)

        get_param_reg pls =
            let l2 = unzip $ map (\(t, Identifier i) -> ((\t -> case t of TInt -> 4; TChar -> 1) t, i)) pls
                regs = map (\a -> show a ++ "(%rbp)") $ [-4,-8..(-24)] ++ [16,32..]
            in zip (snd l2) $ zip regs $ fst l2 -- (name, (reg, size))

        for_pl pls =
            let pl = get_param_reg pls
                si = unzip $ map (\(_,(_,c))->case c of 4->(1,"movl"); 1->(3,"movb")) pl
                reg = map (\inp->(registers!!inp)!!(fst si!!(inp-1))) [1..6]
            in map (\(a,b,c)->"\t" ++ a ++ "\t" ++ b ++ ", " ++ c) $ zip3 (snd si) reg $ map (\(_,(b,_))->b) pl


cComdStmt :: Ast -> RegTable -> [String]
cComdStmt (ComdStmt [] vd sl) rgt = cStmtList sl $ cLocalVar vd rgt


cLocalVar :: [Ast] -> RegTable -> RegTable
cLocalVar vds rgt =
    let
        offset :: [Int]
        offset = map (get_reg_offset . head)
            $ filter (not . null)
            $ map (fst . span ("(%rbp)" `isSuffixOf`) . tails)
            $ map (\(_, (b,_))->b) $ Map.toList rgt

        int_var = map trans $ concat $ map take_name [x | x <- vds, is_int x]
        chr_var = map trans $ concat $ map take_name [x | x <- vds, not $ is_int x]

        int_rgt = for_siz 4 int_var (if null offset then 0 else minimum offset) []
        chr_rgt = for_siz 1 chr_var (fst int_rgt) []
    in
        Map.union (snd int_rgt) (snd chr_rgt)
    where
        is_int (VarDef TInt _) = True
        is_int (VarDef TChar _) = False

        trans (Array (Identifier i) (Number n)) = (i, n)
        trans (Identifier i) = (i, 1)

        take_name = \(VarDef _ n) -> n

        for_siz siz ((name, len):xs) oft res = for_siz siz xs (oft - len * siz)
            $ (name, ((show $ oft - siz) ++ "(%rbp)", siz)) : res
        for_siz _ [] oft res = (oft, Map.fromList res)



cStmtList :: Ast -> RegTable -> [String]
cStmtList sl rgt = [""]


