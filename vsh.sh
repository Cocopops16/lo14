#!/bin/bash

# Ce script est la partie client : lancé par la commande "vsh"

function sendCommand() {
  printf "%s\n" "$2 $3" | nc -c $1 8082
}

function transfertFile() {
  sleep 2
  dir=$(pwd | rev | cut -d'/' -f1 | rev)
  cd ..
  tar Jcvf - $dir | nc -c $1 8081 1> /dev/null
  rm receive.tar.xz
  cd $dir
}

function receiveFile() {
  nc -c $1 8081 > send.tar.xz
}

commande=$(echo $1 | cut -c 2-)
if [ $# -eq 4 ]; then
  if [[ $commande = "create" ]]; then
    tar Jcvf receive.tar.xz * 1> /dev/null
    sendCommand $2 $commande $4 & transfertFile $2 & nc $2 $3
  elif [[ $commande = "extract" ]]; then
    sendCommand $2 $commande $4 & receiveFile $2 & nc $2 $3
    tar Jxvf send.tar.xz
    rm send.tar.xz
  elif [[ $commande = "browse" ]]; then
    sendCommand $2 $commande $4 & nc $2 $3
  else
    sendCommand $2 $commande $4 | nc $2 $3
  fi
elif [ $# -eq 3 ]; then
  sendCommand $2 $commande & timeout 0.5s nc $2 $3
else
  echo "commande interrompue, nombre d'arguments invalide"
fi
