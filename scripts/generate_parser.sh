#!/bin/bash
set -e

# Download ANTLR jar if not exists
ANTLR_VERSION="4.13.1"
ANTLR_JAR="antlr-$ANTLR_VERSION-complete.jar"
if [ ! -f "build/$ANTLR_JAR" ]; then
    echo "Downloading ANTLR $ANTLR_VERSION..."
    curl -o "$ANTLR_JAR" "https://www.antlr.org/download/$ANTLR_JAR"
fi

# Generate parser
echo "Generating parser from grammar..."
# First, change to the root of the grammar directory
cd internal/grammar
java -jar "../../build/$ANTLR_JAR" -o ../parser -Dlanguage=Go -package parser Manuscript.g4
cd ../..
echo "Done!" 