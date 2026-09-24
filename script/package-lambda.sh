#!/bin/bash
cd src/logging-system

rm -f function.zip
zip function.zip lambda_function.py

# Si tuvieran dependencias externas en requirements.txt:
# pip install -r requirements.txt -t package/
# cd package && zip -r ../function.zip . && cd ..
# zip -g function.zip lambda_function.py

echo "function.zip generado en src/logging-system/"