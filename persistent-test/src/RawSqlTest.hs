{-# LANGUAGE OverloadedStrings, GADTs #-}

module RawSqlTest where

import Init

import qualified Data.Text as T
import Control.Monad.Trans.Resource (runResourceT)

import PersistTestPetCollarType
import PersistTestPetType
import PersistentTestModels

specs :: Spec
specs = describe "rawSql" $ do
  it "2+2" $ db $ do
      ret <- rawSql "SELECT 2+2" []
      liftIO $ ret @?= [Single (4::Int)]

  it "?-?" $ db $ do
      ret <- rawSql "SELECT ?-?" [PersistInt64 5, PersistInt64 3]
      liftIO $ ret @?= [Single (2::Int)]

  it "NULL" $ db $ do
      ret <- rawSql "SELECT NULL" []
      liftIO $ ret @?= [Nothing :: Maybe (Single Int)]

  it "entity" $ db $ do
      let insert' :: (PersistStore backend, PersistEntity val, PersistEntityBackend val ~ BaseBackend backend, MonadIO m)
                  => val -> ReaderT backend m (Key val, val)
          insert' v = insert v >>= \k -> return (k, v)
      (p1k, p1) <- insert' $ Person "Mathias"   23 Nothing
      (p2k, p2) <- insert' $ Person "Norbert"   44 Nothing
      (p3k, _ ) <- insert' $ Person "Cassandra" 19 Nothing
      (_  , _ ) <- insert' $ Person "Thiago"    19 Nothing
      (a1k, a1) <- insert' $ Pet p1k "Rodolfo" Cat
      (a2k, a2) <- insert' $ Pet p1k "Zeno"    Cat
      (a3k, a3) <- insert' $ Pet p2k "Lhama"   Dog
      (_  , _ ) <- insert' $ Pet p3k "Abacate" Cat
      escape <- ((. DBName) . connEscapeName) `fmap` ask
      person <- getTableName (error "rawSql Person" :: Person)
      name   <- getFieldName PersonName
      let query = T.concat [ "SELECT ??, ?? "
                           , "FROM ", person
                           , ", ", escape "Pet"
                           , " WHERE ", person, ".", escape "age", " >= ? "
                           , "AND ", escape "Pet", ".", escape "ownerId", " = "
                                   , person, ".", escape "id"
                           , " ORDER BY ", person, ".", name
                           ]
      ret <- rawSql query [PersistInt64 20]
      liftIO $ ret @?= [ (Entity p1k p1, Entity a1k a1)
                       , (Entity p1k p1, Entity a2k a2)
                       , (Entity p2k p2, Entity a3k a3) ]
      ret2 <- rawSql query [PersistInt64 20]
      liftIO $ ret2 @?= [ (Just (Entity p1k p1), Just (Entity a1k a1))
                        , (Just (Entity p1k p1), Just (Entity a2k a2))
                        , (Just (Entity p2k p2), Just (Entity a3k a3)) ]
      ret3 <- rawSql query [PersistInt64 20]
      liftIO $ ret3 @?= [ Just (Entity p1k p1, Entity a1k a1)
                        , Just (Entity p1k p1, Entity a2k a2)
                        , Just (Entity p2k p2, Entity a3k a3) ]

  it "order-proof" $ db $ do
      let p1 = Person "Zacarias" 93 Nothing
      p1k <- insert p1
      escape <- ((. DBName) . connEscapeName) `fmap` ask
      let query = T.concat [ "SELECT ?? "
                           , "FROM ", escape "Person"
                           ]
      ret1 <- rawSql query []
      ret2 <- rawSql query [] :: MonadIO m => SqlPersistT m [Entity (ReverseFieldOrder Person)]
      liftIO $ ret1 @?= [Entity p1k p1]
      liftIO $ ret2 @?= [Entity (RFOKey $ unPersonKey p1k) (RFO p1)]

  it "OUTER JOIN" $ db $ do
      let insert' :: (PersistStore backend, PersistEntity val, PersistEntityBackend val ~ BaseBackend backend, MonadIO m)
                  => val -> ReaderT backend m (Key val, val)
          insert' v = insert v >>= \k -> return (k, v)
      (p1k, p1) <- insert' $ Person "Mathias"   23 Nothing
      (p2k, p2) <- insert' $ Person "Norbert"   44 Nothing
      (a1k, a1) <- insert' $ Pet p1k "Rodolfo" Cat
      (a2k, a2) <- insert' $ Pet p1k "Zeno"    Cat
      escape <- ((. DBName) . connEscapeName) `fmap` ask
      let query = T.concat [ "SELECT ??, ?? "
                           , "FROM ", person
                           , "LEFT OUTER JOIN ", pet
                           , " ON ", person, ".", escape "id"
                           , " = ", pet, ".", escape "ownerId"
                           , " ORDER BY ", person, ".", escape "name"]
          person = escape "Person"
          pet    = escape "Pet"
      ret <- rawSql query []
      liftIO $ ret @?= [ (Entity p1k p1, Just (Entity a1k a1))
                       , (Entity p1k p1, Just (Entity a2k a2))
                       , (Entity p2k p2, Nothing) ]

  it "commit/rollback" (caseCommitRollback >> runResourceT (runConn cleanDB))

caseCommitRollback :: Assertion
caseCommitRollback = db $ do
    let filt :: [Filter Person1]
        filt = []

    let p = Person1 "foo" 0

    _ <- insert p
    _ <- insert p
    _ <- insert p

    c1 <- count filt
    c1 @== 3

    transactionSave
    c2 <- count filt
    c2 @== 3

    _ <- insert p
    transactionUndo
    c3 <- count filt
    c3 @== 3

    _ <- insert p
    transactionSave
    _ <- insert p
    _ <- insert p
    transactionUndo
    c4 <- count filt
    c4 @== 4

