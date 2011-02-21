{-# LANGUAGE TemplateHaskell, QuasiQuotes #-}
module Control.Monad.Unpack.TH (unpack1, unpack) where

import Control.Monad
import Control.Monad.Unpack.Class

import Language.Haskell.TH

unpack1 :: Name -> Q [Dec]
unpack1 tycon = do
  TyConI dec <- reify tycon
  case dec of
    DataD cxt _ tyvars [con] _ -> unpacker1 cxt tycon tyvars con

unpack :: Name -> Q [Dec]
unpack tycon = do
  TyConI dec <- reify tycon
  case dec of
    DataD cxt _ tyvars [con] _ -> unpacker cxt tycon tyvars con

conArgs :: Con -> (Name, [Type])
conArgs (NormalC conName args) = (conName, map snd args)
conArgs (RecC conName args) = (conName, [ty | (_, _, ty) <- args])
conArgs (InfixC (_, ty1) conName (_, ty2)) = (conName, [ty1, ty2])
conArgs _ = undefined

tyVarBndrName  :: TyVarBndr -> Name
tyVarBndrName (PlainTV var) = var
tyVarBndrName (KindedTV var _) = var

unpacker1 :: Cxt -> Name -> [TyVarBndr] -> Con -> Q [Dec]
unpacker1 cxt tyCon tyArgs con = case conArgs con of
  (conName, conArgs) -> do
    argNames <- replicateM (length conArgs) (newName "arg")
    let theTy = foldl (\ t0 arg -> t0 `AppT` arg) (ConT tyCon) (map (VarT . tyVarBndrName) tyArgs)
    let inline = InlineSpec True False Nothing
    let pragmas =
	  [PragmaD $ InlineP (mkName "runUnpackedReaderT")
	    inline,
	  PragmaD $ InlineP (mkName "unpackedReaderT")
	    inline]
    funcName <- newName "UnpackedReaderT"
    mName <- newName "m"
    aName <- newName "a"
    fName <- newName "func"
    let decs = 
	  [NewtypeInstD [] ''UnpackedReaderT [theTy, VarT mName, VarT aName]
	    (NormalC funcName [(NotStrict, foldl (\ result argTy -> ArrowT `AppT` argTy `AppT` result)
		  (VarT mName `AppT` VarT aName) conArgs)]) []] ++ pragmas ++ [
	    FunD 'runUnpackedReaderT
	      [Clause [ConP funcName [VarP fName], ConP conName (map VarP argNames)]
		(NormalB (foldl AppE (VarE fName) (map VarE argNames))) []],
	    FunD 'unpackedReaderT
	      [Clause [VarP fName] (NormalB $ ConE funcName `AppE`
		LamE (map VarP argNames) (VarE fName `AppE` (foldl AppE (ConE conName) (map VarE argNames)))) []]]
    return [InstanceD cxt (ConT ''Unpackable `AppT` theTy) decs]

unpacker :: Cxt -> Name -> [TyVarBndr] -> Con -> Q [Dec]
unpacker cxt tyCon tyArgs con = case conArgs con of
  (conName, conArgs) -> do
    argNames <- replicateM (length conArgs) (newName "arg")
    let theTy = foldl (\ t0 arg -> t0 `AppT` arg) (ConT tyCon) (map (VarT . tyVarBndrName) tyArgs)
    let inline = InlineSpec True False Nothing
    let pragmas =
	  [PragmaD $ InlineP (mkName "runUnpackedReaderT")
	    inline,
	  PragmaD $ InlineP (mkName "unpackedReaderT")
	    inline]
    funcName <- newName "UnpackedReaderT"
    mName <- newName "m"
    aName <- newName "a"
    fName <- newName "func"
    let monadStack = foldr (\ argTy stk -> ConT ''UnpackedReaderT `AppT` argTy `AppT` stk)
	  (VarT mName) conArgs
    let decs = 
	  [NewtypeInstD [] ''UnpackedReaderT [theTy, VarT mName, VarT aName]
	    (NormalC funcName [(NotStrict, monadStack `AppT` VarT aName)]) []] ++ pragmas ++ [
	    FunD 'runUnpackedReaderT
	      [Clause [ConP funcName [VarP fName], ConP conName (map VarP argNames)]
		(NormalB (foldl (\ func arg -> InfixE (Just func) (VarE 'runUnpackedReaderT)
				  (Just arg))
		(VarE fName) (map VarE argNames))) []],
	    FunD 'unpackedReaderT
	      [Clause [VarP fName] (NormalB $ ConE funcName `AppE`
		foldr (\ argName func -> VarE 'unpackedReaderT
		  `AppE` LamE [VarP argName] func)
		  (VarE fName `AppE` (foldl AppE (ConE conName) (map VarE argNames)))
		  argNames) []]]
    return [InstanceD cxt (ConT ''Unpackable `AppT` theTy) decs]