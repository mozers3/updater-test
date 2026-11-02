@echo off
title %~n0
chcp 1251>nul
cd /d "%~dp0"

rem Индексируем ВСЕ изменения
git add --all

REM Проверяем, есть ли staged изменения
git diff-index --quiet --cached HEAD --
if errorlevel 1 (
    git commit -m "-"
    git push -u origin HEAD
) else (
    echo No changes to commit.
)

pause
