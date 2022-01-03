#!/bin/bash

# Ce script est la partie client : lancé par la commande "vsh"

commande=$(echo $1 | cut -c 2-)
if [ $# -eq 4 ]; then
  echo "$commande $4" | nc $2 $3
  if [[ $commande = "create" ]]; then
    tar Jcvf receive.tar.xz *
    cat receive.tar.xz | nc -c localhost 8081
    rm receive.tar.xz
  elif [[ $commande = "extract" ]]; then
    nc -c localhost 8081 > send.tar.xz
    tar Jxvf send.tar.xz
    rm send.tar.xz
  fi
elif [ $# -eq 3 ]; then
  echo "$commande" | nc $2 $3
else
  echo "commande interrompue, nombre d'arguments invalide"
fi
