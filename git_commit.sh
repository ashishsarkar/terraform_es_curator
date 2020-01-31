#!/bin/bash

# Script to push the changes
# ************************************
# * 1) It asks which branch to push
# * 2) It asks commit message
# ************************************

git status
read -p "Please type your commit description: " desc
read -p "Please type the branch name: " branch
git add .
git commit -m "$desc"
git push origin "$branch"