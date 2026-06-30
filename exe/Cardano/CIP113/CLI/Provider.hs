module Cardano.CIP113.CLI.Provider (
    UTxOProvider (..),
    UTxO (..),
    UTxORef (..),
    UTxOValue (..),
) where

import Data.Map.Strict (Map)
import Data.Text (Text)

data UTxORef = UTxORef
    { utxoTxId :: !Text
    , utxoIndex :: !Word
    }
    deriving (Show, Eq, Ord)

data UTxOValue = UTxOValue
    { utxoLovelace :: !Integer
    , utxoAssets :: !(Map Text (Map Text Integer))
    }
    deriving (Show, Eq)

data UTxO = UTxO
    { utxoRef :: !UTxORef
    , utxoAddress :: !Text
    , utxoValue :: !UTxOValue
    }
    deriving (Show, Eq)

class UTxOProvider provider where
    queryUTxOsByAddress :: provider -> Text -> IO [UTxO]
    queryUTxOByRef :: provider -> UTxORef -> IO (Maybe UTxO)
