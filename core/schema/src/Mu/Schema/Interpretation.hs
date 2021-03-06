{-# language DataKinds             #-}
{-# language FlexibleContexts      #-}
{-# language FlexibleInstances     #-}
{-# language GADTs                 #-}
{-# language PolyKinds             #-}
{-# language QuantifiedConstraints #-}
{-# language RankNTypes            #-}
{-# language ScopedTypeVariables   #-}
{-# language TypeApplications      #-}
{-# language TypeFamilies          #-}
{-# language TypeOperators         #-}
{-# language UndecidableInstances  #-}
{-|
Description : Interpretation of schemas

This module defines 'Term's which comply with
a given 'Schema'. These 'Term's are the main
form of values used internally by @mu-haskell@.

In this module we make use of 'NP' and 'NS'
as defined by <https://hackage.haskell.org/package/sop-core sop-core>.
These are the n-ary versions of a pair and
'Either', respectively. In other words, 'NP'
puts together a bunch of values of different
types, 'NS' allows you to choose from a bunch
of types.
-}
module Mu.Schema.Interpretation (
  -- * Interpretation
  Term(..), Field(..), FieldValue(..)
, NS(..), NP(..), Proxy(..)
) where

import           Data.Map
import           Data.Proxy
import           Data.SOP

import           Mu.Schema.Definition

-- | Interpretation of a type in a schema.
data Term (sch :: Schema typeName fieldName) (t :: TypeDef typeName fieldName) where
  -- | A record given by the value of its fields.
  TRecord :: NP (Field sch) args -> Term sch ('DRecord name args)
  -- | An enumeration given by one choice.
  TEnum   :: NS Proxy choices    -> Term sch ('DEnum name choices)
  -- | A primitive value.
  TSimple :: FieldValue sch t    -> Term sch ('DSimple t)

-- | Interpretation of a field.
data Field (sch :: Schema typeName fieldName) (f :: FieldDef typeName fieldName) where
  -- | A single field. Note that the contents are wrapped in a @w@ type constructor.
  Field :: FieldValue sch t -> Field sch ('FieldDef name t)

-- | Interpretation of a field type, by giving a value of that type.
data FieldValue (sch :: Schema typeName fieldName) (t :: FieldType typeName) where
  -- | Null value, as found in Avro and JSON.
  FNull      :: FieldValue sch 'TNull
  -- | Value of a primitive type.
  FPrimitive :: t -> FieldValue sch ('TPrimitive t)
  -- | Term of another type in the schema.
  FSchematic :: Term sch (sch :/: t)
             -> FieldValue sch ('TSchematic t)
  -- | Optional value.
  FOption    :: Maybe (FieldValue sch t)
             -> FieldValue sch ('TOption t)
  -- | List of values.
  FList      :: [FieldValue sch t]
             -> FieldValue sch ('TList   t)
  -- | Dictionary (key-value map) of values.
  FMap       :: Ord (FieldValue sch k)
             => Map (FieldValue sch k) (FieldValue sch v)
             -> FieldValue sch ('TMap k v)
  -- | One single value of one of the specified types.
  FUnion     :: NS (FieldValue sch) choices
             -> FieldValue sch ('TUnion choices)

-- ===========================
-- CRAZY EQ AND SHOW INSTANCES
-- ===========================

instance All (Eq `Compose` Field sch) args
         => Eq (Term sch ('DRecord name args)) where
  TRecord xs == TRecord ys = xs == ys
instance (KnownName name, All (Show `Compose` Field sch) args)
         => Show (Term sch ('DRecord name args)) where
  show (TRecord xs) = "record " ++ nameVal (Proxy @name) ++ " { " ++ printFields xs ++ " }"
    where printFields :: forall fs. All (Show `Compose` Field sch) fs
                      => NP (Field sch) fs -> String
          printFields Nil         = ""
          printFields (x :* Nil)  = show x
          printFields (x :* rest) = show x ++ ", " ++ printFields rest
instance All (Eq `Compose` Proxy) choices => Eq (Term sch ('DEnum name choices)) where
  TEnum x == TEnum y = x == y
instance (KnownName name, All KnownName choices, All (Show `Compose` Proxy) choices)
         => Show (Term sch ('DEnum name choices)) where
  show (TEnum choice) = "enum " ++ nameVal (Proxy @name) ++ " { " ++ printChoice choice ++ " }"
    where printChoice :: forall cs. All KnownName cs => NS Proxy cs -> String
          printChoice (Z p) = nameVal p
          printChoice (S n) = printChoice n
instance Eq (FieldValue sch t) => Eq (Term sch ('DSimple t)) where
  TSimple x == TSimple y = x == y
instance Show (FieldValue sch t) => Show (Term sch ('DSimple t)) where
  show (TSimple x) = show x

instance (Eq (FieldValue sch t)) => Eq (Field sch ('FieldDef name t)) where
  Field x == Field y = x == y
instance (KnownName name, Show (FieldValue sch t))
         => Show (Field sch ('FieldDef name t)) where
  show (Field x) = nameVal (Proxy @name) ++ ": " ++ show x

instance Eq (FieldValue sch 'TNull) where
  _ == _ = True
instance Eq t => Eq (FieldValue sch ('TPrimitive t)) where
  FPrimitive x == FPrimitive y = x == y
instance Eq (Term sch (sch :/: t)) => Eq (FieldValue sch ('TSchematic t)) where
  FSchematic x == FSchematic y = x == y
instance Eq (FieldValue sch t) => Eq (FieldValue sch ('TOption t)) where
  FOption x == FOption y = x == y
instance Eq (FieldValue sch t) => Eq (FieldValue sch ('TList t)) where
  FList x == FList y = x == y
instance (Eq (FieldValue sch k), Eq (FieldValue sch v))
         => Eq (FieldValue sch ('TMap k v)) where
  FMap x == FMap y = x == y
instance All (Eq `Compose` FieldValue sch) choices
         => Eq (FieldValue sch ('TUnion choices)) where
  FUnion x == FUnion y = x == y

instance Ord (FieldValue sch 'TNull) where
  compare _ _ = EQ
instance Ord t => Ord (FieldValue sch ('TPrimitive t)) where
  compare (FPrimitive x) (FPrimitive y) = compare x y
instance Ord (Term sch (sch :/: t)) => Ord (FieldValue sch ('TSchematic t)) where
  compare (FSchematic x) (FSchematic y) = compare x y
instance Ord (FieldValue sch t) => Ord (FieldValue sch ('TOption t)) where
  compare (FOption x) (FOption y) = compare x y
instance Ord (FieldValue sch t) => Ord (FieldValue sch ('TList t)) where
  compare (FList x) (FList y) = compare x y
instance (Ord (FieldValue sch k), Ord (FieldValue sch v))
         => Ord (FieldValue sch ('TMap k v)) where
  compare (FMap x) (FMap y) = compare x y
instance ( All (Ord `Compose` FieldValue sch) choices
         , All (Eq  `Compose` FieldValue sch) choices )
         => Ord (FieldValue sch ('TUnion choices)) where
  compare (FUnion x) (FUnion y) = compare x y

instance Show (FieldValue sch 'TNull) where
  show _ = "null"
instance Show t => Show (FieldValue sch ('TPrimitive t)) where
  show (FPrimitive x) = show x
instance Show (Term sch (sch :/: t)) => Show (FieldValue sch ('TSchematic t)) where
  show (FSchematic x) = show x
instance Show (FieldValue sch t) => Show (FieldValue sch ('TOption t)) where
  show (FOption Nothing)  = "none"
  show (FOption (Just x)) = "some(" ++ show x ++ ")"
instance Show (FieldValue sch t) => Show (FieldValue sch ('TList t)) where
  show (FList xs) = show xs
instance (Show (FieldValue sch k), Show (FieldValue sch v))
         => Show (FieldValue sch ('TMap k v)) where
  show (FMap x) = show x
instance All (Show `Compose` FieldValue sch) choices
         => Show (FieldValue sch ('TUnion choices)) where
  show (FUnion x) = show x
