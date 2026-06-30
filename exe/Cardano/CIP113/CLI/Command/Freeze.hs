module Cardano.CIP113.CLI.Command.Freeze (
    Options (..),
    parser,
    run,
) where

import Options.Applicative (Parser)
import System.Exit (ExitCode (ExitFailure), exitWith)
import System.IO (hPutStrLn, stderr)

data Options = Options
    deriving (Show, Eq)

parser :: Parser Options
parser = pure Options

run :: Bool -> Options -> IO ()
run jsonOutput Options = do
    if jsonOutput
        then putStrLn "{\"error\":\"freeze not yet implemented\"}"
        else hPutStrLn stderr "freeze: not yet implemented"
    exitWith (ExitFailure 2)
