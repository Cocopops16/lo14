#!/bin/bash

# Ce script implémente un serveur.
# Le script doit être invoqué avec l'argument :
# PORT   le port sur lequel le serveur attend ses clients

if [ $# -ne 1 ]; then
    echo "Erreur, port manquant"
    exit -1
fi

PORT="$1"

# Déclaration du tube

FIFO="/tmp/$USER-fifo-$$"

# Il faut détruire le tube quand le serveur termine pour éviter de
# polluer /tmp.  On utilise pour cela une instruction trap pour être sur de
# nettoyer même si le serveur est interrompu par un signal.

function nettoyage() { rm -f "$FIFO"; }
trap nettoyage EXIT

# on crée le tube nommé

[ -e "FIFO" ] || mkfifo "$FIFO"

function accept-loop() {
    while true; do
		interaction < "$FIFO" | netcat -l -p "$PORT" > "$FIFO"
    done
}

# La fonction interaction lit les commandes du client sur entrée standard
# et envoie les réponses sur sa sortie standard.
#
# 	CMD arg1 arg2 ... argn
#
# alors elle invoque la fonction :
#
#         commande-CMD arg1 arg2 ... argn
#
# si elle existe; sinon elle envoie une réponse d'erreur.

browseMode=false
currentDir='0'
browseArchive="0"
browseRoot="0"

#Fonction interaction avec l'utilisateur
function interaction() {
    local cmd args
    x=0
    while true; do
      if [[ $x -eq 0 ]]; then
        cmd=$(nc -l -p 8082)
        if [[ ! -z $cmd ]]; then
          args=$(echo $cmd | cut -d" " -f2)
          cmd=$(echo $cmd | cut -d" " -f1)
        fi
      else
        read -r cmd args || exit -1
      fi
  		if $browseMode; then #Si browsemode est vrai (Si l'user invoque la fonction browse)
  			fun="browse-$cmd"
      elif [[ -z $cmd && $x -eq 0 ]]; then
        fun="commande-browse"
        echo "$x $fun"
        echo "args recup : $args"
  		else
  			fun="commande-$cmd"
  		fi
  		if [ "$(type -t $fun)" = "function" ]; then
  	    $fun $args
  	  elif [ "$fun" = "browse-exit" ]; then #Si je quitte browsemode
  	    browseMode=false
  		else
        commande-non-comprise $fun $args
  		fi
  		if $browseMode; then
  			echo -n "vsh:>"
  		fi
      ((x++))
    done
}

# Les fonctions implémentant les différentes commandes du serveur

function commande-list() {
	ls=$(ls archives)
	if [ -n "$ls" ]; then
		echo "Les archives présentes sur le serveur sont :"
		echo $ls
	else
		echo "Pas d'archives présente sur le serveur"
	fi
}

function browse-mkdir() {
  if [[ "$1" = "-p" ]]; then
    directory=$2
  fi
}

function addDir() {
  dirArborescence=$(echo $1 | sed 's/\//\\/g')
  newDirName=$2
  nomArchive=$3
  cheminFichier=tmp_receive/$4
  echo "directory $dirArborescence\\$newDirName" >> archives/$nomArchive
  ls -l $cheminFichier | awk 'NR>1{n=split($1,tab,""); if(tab[1]=="d")print $9" "$1" "$5;}' >> archives/$nomArchive
  ls -l $cheminFichier | awk 'NR>1{n=split($1,tab,""); if(tab[1]=="-")print $9" "$1" "$5;}END{print "@"}' >> archives/$nomArchive
}

function commande-create() {
    echo "Mode create"
    nomArchive=$1 #Argument (Nom de l'archive)
  	if [ -n "$nomArchive" ]; then
  		occurence=false #Flag false
  		for i in $(ls archives); do
  			if [ "$nomArchive" = "$i" ]; then
  				occurence=true
  				break
  			fi
  		done

  		if $occurence; then
  			echo "création impossible, une archive porte déjà ce nom"
  		else
        echo "reception des fichiers"
        cd tmp_receive
        nc -l -p 8081 > receive.tar.xz
        tar Jxvf receive.tar.xz
        rm receive.tar.xz
        cd ..

        if [ -z "$(ls tmp_receive)" ];
        then
          echo "erreur lors du transfert"
        else
          echo "arborescence bien reçue"
          echo "3:5" >> archives/$nomArchive #Sinon, on met tout en haut du fichier 3:5 comme dans l'énoncé et on crée automatiquement le fichier avec >>
          dir=$(ls tmp_receive)
          ls -l tmp_receive/$dir | awk -v dir=$dir 'BEGIN{print "\ndirectory "dir}NR>1{n=split($1,tab,""); if(tab[1]=="d")print $9" "$1" "$5;}' >> archives/$nomArchive
          ls -l tmp_receive/$dir | awk 'NR>1{n=split($1,tab,""); if(tab[1]=="-")print $9" "$1" "$5;}END{print "@"}' >> archives/$nomArchive
          export -f addDir
          awk  -v nomArchive=$nomArchive '{if($1=="directory"){dirArborescence=$2; gsub(/\\/, "/", dirArborescence); getline; while($1!="@"){n2=split($2,tab2,""); if(tab2[1]=="d"){cmd="addDir "dirArborescence" "$1" "nomArchive" "dirArborescence"/"$1";"; system(cmd);}; getline}}}' archives/$nomArchive

          root=$(cat archives/$nomArchive | awk 'BEGIN{ligneCandidate=""; nbrChamps=""; m=0}NR>2{if($1=="directory"){line=$0; n=split($2,tab,"\\");getline; if($1!="@"){ligneCandidate=ligneCandidate" "line; nbrChamps=nbrChamps" "n; m=m+1}}}END{split(ligneCandidate,tab2," "); split(nbrChamps,tab3," "); min=100; indice=1; for(i=1; i<=m; i++){if(tab3[i]<min){min=tab3[i]; indice=i}}indice=indice*2; print tab2[indice]}')
          sed -i "s/^directory $root$/&\\\/g" archives/$nomArchive

          nbrLinesHeader=$(wc -l archives/test | cut -d' ' -f1)
          sed -i "1s/3:5/3:$nbrLinesHeader/" archives/$nomArchive

          echo "traitment des données de chaque fichier"
          while read -r line; do
            if [[ -z $(echo $line | grep '^@') ]]; then
              if [[ -z $(echo $line | grep '^directory') ]]; then
                type=$(echo $line | awk '{split($2,tab,""); print tab[1]}')
                if [ ! -z $(echo $type | grep '^-') ]; then
                  fileName=$(echo $line | awk '{print $1}')
                  startLine=$(wc -l archives/$nomArchive | cut -d' ' -f1)
                  ((startLine++))
                  nbrLinesFile=$(wc -l $chemin/$fileName | cut -d' ' -f1)
                  ((endLine=startLine+nbrLinesFile-1))
                  sed -i "s/^$fileName.*$/& $startLine $endLine/g" archives/$nomArchive
                  cat $chemin/$fileName >> archives/$nomArchive
                fi
              else
                chemin=$(printf "%s\n" "$line" | awk '{split($2,tab,/test\\/); gsub(/\\/, "/", tab1[2]); print tab[2]}')
                chemin=$(printf "%s\n" "$chemin" | sed 's/\\/\//g')
                chemin=tmp_receive/$chemin
              fi
            fi
          done < archives/$nomArchive

    			echo "Le fichier a été créé avec succès"
        fi
  		fi
      rm -r tmp_receive/*
  	else
  		echo "création impossible, pas de nom fourni pour l'archive"
  	fi
}


#Fonction invoquer browse
function commande-browse() {
	browseArchive=$1 #Argument
	if [ -n "$browseArchive" ]
	then #Si argument est une chaine non vide (Donc il existe)
		trouve=$(ls archives | grep -c $browseArchive)
		if [ $trouve -eq 0 ]
		then
			echo "Navigation impossible, aucune archive de ce nom sur le serveur"
		else
			browseMode=true
      browseRoot=$(egrep '^directory.*\\$' archives/$browseArchive | cut -d" " -f2)
      currentDir=$browseRoot
		fi
	else
		echo "Navigation impossible, pas de nom fourni pour l'archive"
	fi
}

function browse-pwd() {
	if [[ "$currentDir" = "$browseRoot" ]]; then
    printf "%s\n" '\'
  else
    root=$(printf "%s\n" "$browseRoot" | sed 's/\\/\\\\/g')
    printf "%s\n" $dir | awk -v root=$root '{n=split(root,tab,"\\"); m=split($1,tab2,"\\"); for(i=n;i<=m;i++){final=final"\\"tab2[i]}print final;}'
  fi
}

function browse-cd() {
  dirDestination=$1
  test=$(printf "%s\n" $dirDestination | cut -c1 | sed 's/\\/\\\\/g')
  if [[ ! -z $test ]]; then
    test=$(egrep "^directory.*$test$" archives/exemple | cut -d" " -f2)
  else
    test="0"
  fi
  if [[ "$dirDestination" = '\' ]]; then
    currentDir=$browseRoot
  elif [[ "$dirDestination" = ".." ]]; then
    if [[ "$currentDir" != "$browseRoot" ]]; then
      currentDir=$(printf "%s\n" "$currentDir" | sed 's/\(.*\)\\.*$/\1/')
      test=$currentDir'\'
      if [[ "$test" = "$browseRoot" ]]; then
        currentDir=$test
      fi
    fi
  elif [[  "$test" = "$browseRoot" ]]; then
    dir=$(printf "%s\n" "$dirDestination" | sed 's/\\/\\\\/g')
    dir=$(egrep "^directory.*$dir$" archives/$browseArchive | cut -d" " -f2)
    if [[ -z $dir ]]; then
      echo "pas de dossier $dirDestination connu"
    else
      currentDir=$dir
    fi
  else
    if [[ "$currentDir" = "$browseRoot" ]]; then
      dir=$currentDir$dirDestination
    else
      dir=$currentDir'\'$dirDestination
    fi
    dir=$(printf "%s\n" "$dir" | sed 's/\\/\\\\/g')
    dir=$(egrep "^directory.*$dir$" archives/$browseArchive | cut -d" " -f2)
    if [[ -z $dir ]]; then
      echo "pas de dossier $dirDestination connu"
    else
      currentDir=$dir
    fi
  fi
}

function lsAll() {
  test=$(printf "%s\n" $1 | cut -c1 | sed 's/\\/\\\\/g')
  if [[ ! -z $test ]]; then
    test=$(egrep "^directory.*$test$" archives/exemple | cut -d" " -f2)
  else
    test="0"
  fi
  if [[ -z $1 ]]; then
    dir=$currentDir
  elif [[ "$test" = "$browseRoot" ]]; then
    dir=$browseRoot$(printf "%s\n" $1 | cut -c2-)
  else
    if [[ "$currentDir" = "$browseRoot" ]]; then
      dir=$currentDir$1
    else
      dir=$currentDir'\'$1
    fi
  fi
  dir=$(printf "%s\n" "$dir" | sed 's/\\/\\\\/g')
  printf "%s\n" $dir
}

function browse-ls() {
  case $1 in
    -l )
      dir=$(lsAll $2)
      awk -v dir=$dir 'BEGIN{strDir="directory "dir}{if($0==strDir){getline; while($1!="@"){split($1,tab,"");if(tab[1]!="."){print $2" "$3" "$1} getline}}}' archives/$browseArchive
      ;;
    -a )
      dir=$(lsAll $2)
      awk -v dir=$dir 'BEGIN{strDir="directory "dir}{if($0==strDir){getline; while($1!="@"){ls=ls" "$1; split($2,tab2,"");if(tab2[1]=="d"){ls=ls"\\"}else if(tab2[1]=="-" && (tab2[4]=="x" || tab2[7]=="x" || tab2[10]=="x")){ls=ls"*"} getline} print ls}}' archives/$browseArchive
      ;;
    -la | -al )
      dir=$(lsAll $2)
      awk -v dir=$dir 'BEGIN{strDir="directory "dir}{if($0==strDir){getline; while($1!="@"){print $2" "$3" "$1; getline}}}' archives/$browseArchive
      ;;
    * )
      dir=$(lsAll $1)
      awk -v dir=$dir 'BEGIN{strDir="directory "dir}{if($0==strDir){getline; while($1!="@"){split($1,tab,"");if(tab[1]!="."){ls=ls" "$1} split($2,tab2,"");if(tab2[1]=="d"){ls=ls"\\"}else if(tab2[1]=="-" && (tab2[4]=="x" || tab2[7]=="x" || tab2[10]=="x")){ls=ls"*"} getline} print ls}}' archives/$browseArchive
      ;;
  esac
}


#Fonction extraction
function commande-extract() {
	nomArchive=$1 #Argument
	if [ -z $nomArchive ] #Si aucun argument
	then
		echo "Erreur, aucune archive donnée en argument"
		return
	elif [ -n $nomArchive ]
	then #Si argument, vérifier que l'archive existe bien dans le serveur
	trouve=$(ls archives | grep -c $nomArchive) # Chercher occurence de l'archive dans le serveur
		if [ $trouve -eq 0 ]
             	then
			echo "L'archive n'existe pas dans le serveur"
			return
        	else
			chemin=archives/$nomArchive #Path de l'archive
			debut=$(head -1 $chemin | cut -d":" -f1) #Début du header
			header=$(head -1 $chemin | cut -d":" -f2) # nombre de lignes du header
			cat $chemin > tmp_extract/archive_tmp #Récupération de l'archive dans un fichier temporaire
			sed -i 's/\\/\//g' tmp_extract/archive_tmp # Je remplace les \ par les /
			i=0
			while read ligne #Lecture ligne par ligne du fichier temporaire avec que le contenu du header
			do
			        i=$((i+1)) #Compteur pour savoir si on est encore dans le header ou non
			        if [ "$i" -lt "$debut" ]; then # Si le compteur est plus petit que la ligne de debut du header, skip
                                    continue
                                fi
			        if [ "$i" -eq "$header" ]; then # Si le compteur est égale à la dernière ligne du header
				    break #Je quitte la boucle
				fi
				set $ligne # On prend les arguments de chaque ligne
				if [[ "$ligne" == "@"* ]]; then #Si la ligne est égale à @, on skip
				    continue
				fi
				if [[ "$ligne" == "directory"* ]] # Vrai si la ligne commence par directory
				then
					arbo_doss=$(echo $ligne | awk '{print $2}') # Si ça commence par directory, je prend le field 2 qui correspond à l'arbo
					mkdir -p tmp_extract/$arbo_doss # Création avec mkdir l'arbo avec l'option -parents
				elif [[ ! "$ligne" =~ "directory"* ]] # Sinon, si ce n'est pas un directory
				then
					rights=$(echo $ligne | awk '{print $2}') # Récupération des droits
					name=$(echo $ligne | awk '{print $1}') # Récupération des noms
					if [[ "$rights" == "d"* ]] # Si les droits commencent par un d alors je sais que c'est un sous-dossier
					then
						mkdir -m 755 tmp_extract/$arbo_doss/$name # Je fais un mkdir avec chmod 755 pour un sous dossier dans le repertoire main
					elif [[ "$rights" == "-"* ]]
					then
						touch tmp_extract/$arbo_doss/$name # Création d'un fichier vide dans le repertoire main avec le nom enregistré
						roctale=$(echo "$rights" | sed 's/.\(.........\).*/\1/
    						h;y/rwsxtSTlL-/IIIIIOOOOO/;x;s/..\(.\)..\(.\)..\(.\)/|\1\2\3/
    						y/sStTlLx-/IIIIIIOO/;G
    						s/\n\(.*\)/\1;OOO0OOI1OIO2OII3IOO4IOI5IIO6III7/;:k
    						s/|\(...\)\(.*;.*\1\(.\)\)/\3|\2/;tk
    						s/^0*\(..*\)|.*/\1/;q') # Conversion notation symbolique vers octale
						chmod $roctale tmp_extract/$arbo_doss/$name # J'applique les droits respectifs à chaque fichier
					        taille=$(echo "$ligne" | awk '{print $3}') #Si taille differente de zero, récupération du contenu
                                             	if [ "$taille" -ne 0 ] #Sinon, je passe la ligne (Aucun contenu à récuperer)
                                             	then
                                                     bodycommence=$((header-1+$(echo "$ligne" | cut -d" " -f4))) #Récupération òu le contenu commence
						     bodyetendre=$(echo "$ligne" | awk '{print $5}')
						     if [ 0 -eq "$bodyetendre" ]; then #Si fichier vide (Aucune info complementaire, on skip on cherche pas le contenu)
						         continue
					             fi
						     bodyetendre=$((bodycommence-1+bodyetendre)) #Recuperer jusqu'où le contenu s'etendre
                                                     contenu=$(cat "tmp_extract/archive_tmp" | sed -n "$bodycommence,$bodyetendre p") #Contenu de chaque fichier à mettre dans le fichier en question
					             echo "$contenu" > "tmp_extract/$arbo_doss/$name" #Transfert du contenu dans le fichier respectif
                                             	fi

					fi
				fi
			done < tmp_extract/archive_tmp #Lecture
               fi
	fi

  cd tmp_extract
  rm archive_tmp
  tar Jcvf send.tar.xz *
  cat send.tar.xz | nc -l -p 8081
  cd ..
  rm -rf tmp_extract/*

  echo "Extraction terminée"
}

function browse-touch() {
  path="archives/"$browseArchive
	cheminFichier=$1
  if [ -z $cheminFichier ]
  then
		echo "Erreur, argument manquant"
	elif [ -n $cheminFichier ]
	then
		nomFichier=$(echo $cheminFichier | rev | cut -d"\\" -f 1 | rev) # Récupération du nom du fichier entré par l'user ( Dernier champ )
		occurence=$(grep -c $nomFichier $path) #Chercher si le fichier existe dans le fichier texte ( Je cherche si le nom apparait dans une ligne )
		if [[ $occurence -ne 0 ]]
		then
			echo "Le fichier existe déjà dans l'archive"
			return
		else
			arbo=$(echo $cheminFichier | rev | cut -d "\\" -f2- | rev) #Récupération de l'arbo donné par l'user avec des commandes CUT
			replace=$(echo $arbo | sed 's/\\/\\\\/g') #Echapper les '\' pour éviter les bugs avec Grep
			occurence2=$(grep -c $replace $path) #Je regarde s'il y a occurence de l'arbo dans le fichier texte
			match=$(echo $replace | rev | cut -d"\\" -f1 | rev) #Prendre le dernier champ de l'arbo pour que sed puisse match une ligne ET une seule
			if [[ $occurence2 -ne 0 ]] #Si occurence est different de 0, l'arbo existe (Chaine trouvée) donc je peux insérer mon fichier
			then
				sed -i "/\($match\)\\\\*$/a $nomFichier -rw-rw-r-- 0 0 0" "$path" #Insertion du fichier vide au bon endroit (En dessous de la ligne finissant par $match regex)
				echo "Fichier vide inséré dans l'archive avec succès !"
				header=$(head -1 $path | cut -d":" -f2)
				let header2="$header"+1
				sed -i "1s/$header/$header2/" $path #Augmenter compteur header car insertion fichier
			else
				echo "L'arborescence décrite n'existe pas dans l'archive"
				return	#Pas d'arbo existente donc erreur
			fi
		fi
	fi
} #Fixer Luser qui rentre des \\

function browse-cat() {
  path="archives/"$browseArchive
	if [ $# -eq 1 ]
	then
		header=$(head -1 $path | cut -d":" -f2) #Nombre de lignes du header
		w=$(cat "$path" | wc -l) #Nbre de lignes total de l'archive
		let body="$w"-"$header"+2 #Nombre de lignes du body
		contenu=$(cat "$path" | tail -"$body") #Récupération du body
		fichier1=$1
		nomfich=$(echo "$fichier1" | rev | cut -d"\\" -f1 | rev) #Récuperer nom fichier entré par l'utilisateur
		occurence=$(grep -c $nomfich $path) # Chercher si le fichier existe dans l'archive
		taille=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f3) #Récuperer la taille du fichier
		type=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f2) #Récuperer le type (si fich ou doss)
		if [[ "$taille" -eq 0 ]] && [[ $occurence -ne 0 ]]
		then
			echo "Fichier vide. Aucun contenu à afficher"
			return
		fi
		if [[ "$type" == "d"* ]]
		then
			echo "Erreur, il s'agit d'un dossier"
			return
		fi
		if [[ $occurence -eq 0 ]]
		then
			echo "Fichier n'existe pas"
			return
		else
			arbo=$(echo "$fichier1" | rev | cut -d"\\" -f2- | rev) #Verifier que arbo existe
			replace=$(echo "$arbo" | sed 's/\\/\\\\/g') #Echapper les '\'
			occurence2=$(grep -c $replace $path) #Occurence de l'arbo ?
			if [[ $occurence2 -eq 0 ]]
			then
				echo "Arbo existe pas"
				return
			else
				 bodycommence=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f4)
				 let bodycommence="$bodycommence"+1
				 bodyetendre=$(cat "$path" | grep "^"$nomfich"" | awk '{print $5}') #Recuperer pour la ligne le nombre de lignes du body
				 let bodyetendre="$bodyetendre"+1
				 afficher=$(echo "$contenu" | sed -n "$bodycommence,$bodyetendre p") # J'affiche le contenu du fichier
				 echo "Voici l'archive souhaitée :"
				 echo "$afficher"
			fi
		fi
	elif [ $# -eq 2 ]
	then
		fichier1=$1
		fichier2=$2
                header=$(head -1 $path | cut -d":" -f2) #Nombre de lignes du header
		w=$(cat "$path" | wc -l) #Nbre de lignes total de l'archive
		let body="$w"-"$header"+2 #Nombre de lignes du body
		contenu=$(cat "$path" | tail -"$body") #Récupération du body
		nomfich=$(echo "$fichier1" | rev | cut -d"\\" -f1 | rev) #Récuperer nom fichier entré par l'utilisateur
		nomfich2=$(echo "$fichier2" | rev | cut -d"\\" -f1 | rev) #Récuperer nom fichier entré par l'utilisateur
		occurence=$(grep -c $nomfich $path) # Chercher si le fichier existe dans l'archive
		occurencefich2=$(grep -c $nomfich2 $path) #Chercher si le fichier 2 existe dans l'archive
		taille=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f3) #Récuperer la taille du fichier
		taille2=$(cat "$path" | grep "^"$nomfich2"" | cut -d" " -f3)
		type=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f2) #Récuperer le type (si fich ou doss)
		type2=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f2)
		if [[ "$taille" -eq 0 ]] && [["$taille2" -eq 0 ]] && [[ "$occurence" -ne 0 ]] && [[ "$occurencefich2" -ne 0 ]]
		then
			echo "Les fichiers sont vides. Aucun contenu à afficher"
			return
		fi
		if [[ "$type" == "d"* ]] && [[ "$type2" == "d"* ]]
		then
			echo "Erreur, ce sont des dossiers"
			return
		fi
		if [[ $occurence -eq 0 ]] && [[ $occurencefich2 -eq 0 ]]
		then
			echo "Les fichiers n'existent pas"
			return
		else
			arbo=$(echo "$fichier1" | rev | cut -d"\\" -f2- | rev) #Verifier que arbo existe
			arbo2=$(echo "$fichier2" | rev | cut -d"\\" -f2- | rev)
			replace=$(echo "$arbo" | sed 's/\\/\\\\/g') #Echapper les '\'
			replace2=$(echo "$arbo2" | sed 's/\\/\\\\/g')
			occurence2=$(grep -c $replace $path) #Occurence de l'arbo ?
			occurence3=$(grep -c $replace2 $path)
			if [[ $occurence2 -eq 0 ]] && [[ $occurence3 -eq 0 ]]
			then
				echo "Les Arbos existe pas"
				return
			else
				 bodycommence=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f4)
				 bodycommence2=$(cat "$path" | grep "^"$nomfich2"" | cut -d" " -f4)
				 let bodycommence="$bodycommence"+1
				 let bodycommence2="$bodycommence2"+1
				 bodyetendre=$(cat "$path" | grep "^"$nomfich"" | awk '{print $5}') #Recuperer pour la ligne le nombre de lignes du body
				 bodyetendre2=$(cat "$path" | grep "^"$nomfich2"" | awk '{print $5}')
				 let bodyetendre="$bodyetendre"+1
				 let bodyetendre2="$bodyetendre2"+1
				 afficher=$(echo "$contenu" | sed -n "$bodycommence,$bodyetendre p") # J'affiche le contenu du fichier
				 afficher2=$(echo "$contenu" | sed -n "$bodycommence2,$bodyetendre2 p")
				 echo "Voici les archives souhaitées :"
				 echo "$afficher"
				 echo "-----------------"
				 echo "$afficher2"
			fi
		fi

	else
		echo "Erreur, aucun argument ou trop d'arguments"
		return
	fi
}

function commande-non-comprise() {
   echo "Le serveur ne peut pas interpréter cette commande"
}

# On accepte et traite les connexions

accept-loop
