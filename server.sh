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
currentDirectory='\'

#Fonction interaction avec l'utilisateur
function interaction() {
    local cmd args
    while true; do
		read cmd args || exit -1
		if $browseMode; then #Si browsemode est vrai (Si l'user a invoquer la fontion browsemode)
			fun="browse-$cmd" #browse-commande tapée stockée
		else
			fun="commande-$cmd" #SI browsemode a pas été appellée alors le serveur attend autre commande
		fi
		if [ "$(type -t $fun)" = "function" ]; then
	    	$fun $args
	    elif [ "$fun" = "browse-exit" ]; then #Si je quitte browsemode, alors je retourne en saisi de commande classique
	    	browseMode=false
		else
		   	commande-non-comprise $fun $args
		fi
		if $browseMode; then #SI jsuis en browse mode, j'affiche vsh
			echo -n "vsh:>"
		fi
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

function addDir() {
  dirArborescence=$(echo $1 | sed 's/\//\\/g')
  newDirName=$2
  nomArchive=$3
  cheminFichier=tmp_receive/$4
  echo $dirArborescence $newDirName $nomArchive $cheminFichier
  echo "directory $dirArborescence\\$newDirName" >> archives/$nomArchive
  ls -l $cheminFichier | awk 'NR>1{n=split($1,tab,""); if(tab[1]=="d")print $9" "$1" "$5;}' >> archives/$nomArchive
  ls -l $cheminFichier | awk 'NR>1{n=split($1,tab,""); if(tab[1]=="-")print $9" "$1" "$5;}END{print "@"}' >> archives/$nomArchive
}

function commande-create() {
    nomArchive=$1 #Argument saisie (Nom de l'archive)
  	if [ -n "$nomArchive" ]; then #SI l'argument saisie est pas vide
  		occurence=false #Flag a false
  		for i in $(ls archives); do #On a crée au préalable un dossier archive qui va contenir toutes les archives
  			if [ "$nomArchive" = "$i" ]; then #SI on veut crée un une archive avec le meme nom
  				occurence=true #Occurence = true
  				break
  			fi
  		done

  		if $occurence; then #SI TRUE alors impossible de créer logique !
  			echo "création impossible, une archive porte déjà ce nom"
  		else
        mkdir tmp_receive
        cd tmp_receive
        nc -l -p 8081 > receive.tar.xz
        tar Jxvf receive.tar.xz
        rm receive.tar.xz
        cd ..

        if [ -z "$(ls tmp_receive)" ];
        then
          echo "erreur lors du transfert"
          ##cd ..
          #rmdir $$
        else
          echo "arborescence bien reçue"
          echo "3:5" >> archives/$nomArchive #Sinon, on met tout en haut du fichier 3:5 comme dans l'énoncé et on crée automatique le fichier avec >>
          ls -l tmp_receive | awk -v nomArchive=$nomArchive 'BEGIN{print "\ndirectory "nomArchive}NR>1{n=split($1,tab,""); if(tab[1]=="d")print $9" "$1" "$5;}' >> archives/$nomArchive
          ls -l tmp_receive | awk 'NR>1{n=split($1,tab,""); if(tab[1]=="-")print $9" "$1" "$5;}END{print "@"}' >> archives/$nomArchive
          export -f addDir
          awk  -v nomArchive=$nomArchive '{if($1=="directory"){dirArborescence=$2; gsub(/\\/, "/", dirArborescence); split($2,tab1,/test\\/); gsub(/\\/, "/", tab1[2]); cheminFichier=tab1[2]; getline; while($1!="@"){n2=split($2,tab2,""); if(tab2[1]=="d"){cmd="addDir "dirArborescence" "$1" "nomArchive" "cheminFichier"/"$1";"; system(cmd);}; getline}}}' archives/$nomArchive

          nbrLinesHeader=$(wc -l archives/test | cut -d' ' -f1)
          sed -i "1s/3:5/3:$nbrLinesHeader/" archives/test

          while read -r line; do
            if [[ -z $(echo $line | grep '^@') ]]; then
              if [[ -z $(echo $line | grep '^directory') ]]; then
                type=$(echo $line | awk '{split($2,tab,""); print tab[1]}')
                echo $line
                echo $type
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
                echo $chemin
              fi
            fi
          done < archives/$nomArchive

    			echo "Le fichier a été créé avec succès"
        fi
  		fi
  	else
  		echo "création impossible, pas de nom fourni pour l'archive"
  	fi
}


#Fonction invoquer browse
function commande-browse() {
	eval nomArchive=$1 #Argument
	if [ -n "$nomArchive" ]
	then #Si argument est une chaine non vide (Donc il existe)
		trouve=$(ls archives | grep -c $nomArchive)
		if [ $trouve -eq 0 ]
		then
			echo "Navigation impossible, aucune archive de ce nom sur le serveur"
		else
			browseMode=true
			eval path=archives/$nomArchive
		fi
	else
		echo "Navigation impossible, pas de nom fourni pour l'archive" #Sinon on dit qu'on peut pas car aucun nom fourni (où le serveur peut aller ?)
	fi
}

function browse-pwd() {
	echo $currentDirectory
}

#Fonction extraction
function commande-extract() {
	nomArchive=$1 #Argument (Le nom de l'archive que l'utilisateur souhaite extraire le contenu pour la mettre sur sa machine !)
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
			header=$(head -1 $chemin | cut -d":" -f2) #Je recupère le nombre de lignes du header
			cat $chemin > tmp_extract/archive_tmp #Récupération de l'entierete de l'archive dans un fichier temporaire
			sed -i 's/\\/\//g' tmp_extract/archive_tmp # Je remplace les \ par les / dans le tmp_full
			i=0
			while read ligne #Lecture ligne par ligne du fichier temporaire avec que le contenu du header #Boucle pour créer les dossiers fich sous dossiers
			do
			        i=$((i+1)) #Compteur pour savoir si on est encore dans le header ou non
			        if [ "$i" -lt "$debut" ]; then # Si le compteur est plus petit que la ligne de debut du header, on skip
                                    continue
                                fi
			        if [ "$i" -eq "$header" ]; then # Si le compteur est égale à la dernière ligne du header
				    break #Je quitte la boucle
				fi
				set $ligne # On prend les arguments de chaque ligne séparés par un espace
				if [[ "$ligne" == "@"* ]]; then #Si la ligne est égale à @, on skip
				    continue
				fi
				if [[ "$ligne" == "directory"* ]] # Vrai si la ligne commence par directory
				then
					arbo_doss=$(echo $ligne | awk '{print $2}') # Si ca commence par directory, je prend le field 2 qui correspond à l'arbo
					mkdir -p tmp_extract/$arbo_doss # Je crée avec mkdir l'arbo avec l'option -parents
				elif [[ ! "$ligne" =~ "directory"* ]] # Sinon, si c pas un directory main
				then
					rights=$(echo $ligne | awk '{print $2}') # Je recupere les droits
					name=$(echo $ligne | awk '{print $1}') # Je recupere le nom
					if [[ "$rights" == "d"* ]] # Si les droits commence par un d alors je sais que c un sous-dossier
					then
						mkdir -m 755 tmp_extract/$arbo_doss/$name # Je fais un mkdir avec chmod 755 pour un sous dossier dans le repertoire main
					elif [[ "$rights" == "-"* ]]
					then
						touch tmp_extract/$arbo_doss/$name # Je créer un fichier vide dans le repertorie main avec le nom enregistré
						roctale=$(echo "$rights" | sed 's/.\(.........\).*/\1/
    						h;y/rwsxtSTlL-/IIIIIOOOOO/;x;s/..\(.\)..\(.\)..\(.\)/|\1\2\3/
    						y/sStTlLx-/IIIIIIOO/;G
    						s/\n\(.*\)/\1;OOO0OOI1OIO2OII3IOO4IOI5IIO6III7/;:k
    						s/|\(...\)\(.*;.*\1\(.\)\)/\3|\2/;tk
    						s/^0*\(..*\)|.*/\1/;q') # A partir des caracteres, je prends la notation octale quelque soit la combi de droits
						chmod $roctale tmp_extract/$arbo_doss/$name # J'applique les droits respectifs à chaque fichier
					        taille=$(echo "$ligne" | awk '{print $3}') #Si taille differente de zero, je recupere le contenu
                                             	if [ "$taille" -ne 0 ] #Sinon, je passe la ligne (Aucun contenu à récuperer)
                                             	then
                                                     bodycommence=$((header-1+$(echo "$ligne" | cut -d" " -f4))) #Recuperer la ligne ou le contenu commence
						     bodyetendre=$(echo "$ligne" | awk '{print $5}')
						     if [ 0 -eq "$bodyetendre" ]; then #Si fichier vide (Aucune infos complementaires, on skip on cherche pas le contenu)
						         continue
					             fi
						     bodyetendre=$((bodycommence-1+bodyetendre)) #Recuperer jusqu'où le contenu s'etendre
                                                     contenu=$(cat "tmp_extract/archive_tmp" | sed -n "$bodycommence,$bodyetendre p") #Contenu de chaque fichier à mettre dans le fichier en question
					             echo "$contenu" > "tmp_extract/$arbo_doss/$name" #Transfert du contenu adéquat dans le fichier respectif
                                             	fi

					fi
				fi
			done < tmp_extract/archive_tmp #Je lis le contenu du fichier temporaire avec que le header
               fi
	fi

  cd tmp_extract
  rm archive_tmp
  tar Jcvf send.tar.xz *
  cat send.tar.xz | nc -l -p 8081
  cd ..
  rm -rf tmp_extract/*

	echo "Extraction terminée"
} #Reste a  TAR + Transfert des fichiers via netcat au client

#Fonction pour insérer une ligne dans l'archive (Fichier vide) à l'endroit spécifié par l'utilisateur et dans l'archive donné par l'user
function browse-touch() {
	cheminFichier=$1 #Chemin du fichier entré par l"utilisateur  ( Dans quel dossier je dois foutre le fichier vide ) (Me donne la ligne où inserer mon fichier vide dans le texte !)
	if [ -z $cheminFichier ]
	then
		echo "Erreur, argument manquant"
		return
	elif [ -n $cheminFichier ] # l'argument est entré
	then

		nomFichier=$(echo $cheminFichier | rev | cut -d"\\" -f 1 | rev) # Je récupère la nom du fichier entré par l'user ( Dernier champ )
		occurence=$(grep -c $nomFichier $path) #Chercher si le fichier existe dans le fichier texte ( Je cherche si le nom apparait dans une ligne )
		if [[ $occurence -ne 0 ]]
		then
			echo "Le fichier existe déjà dans l'archive"
			return
		else
			arbo=$(echo $cheminFichier | rev | cut -d "\\" -f2- | rev) #Je recupère l'arbo donné par l'user avec des commandes CUT
			replace=$(echo $arbo | sed 's/\\/\\\\/g') #Echapper les '\' pour éviter les bugs avec Grep
			occurence2=$(grep -c $replace $path) #Je regarde s'il y a occurence de l'arbo dans le fichier texte
			match=$(echo $replace | rev | cut -d"\\" -f1 | rev) #Prendre le dernier champ de l'arbo pour que sed puisse match une ligne ET une seule
			if [[ $occurence2 -ne 0 ]] #Si occurence est different de 0, l'arbo existe (Chaine trouvée) donc je peux insérer mon fichier
			then
				sed -i "/\($match\)$/a $nomFichier -rw-rw-r-- 0 0 0" "$path" #Insertion du fichier vide au bon endroit (En dessous de la ligne finissant par $match regex)
				echo "Fichier vide inséré dans l'archive avec succès !"
			else
				echo "L'arborescence décrite n'existe pas dans l'archive"
				return	#Pas d'arbo existente donc erreur
			fi
		fi
	fi
} #Fixer Luser qui rentre des \\

function browse-cat() {

	if [ $# -eq 1 ]
	then
		header=$(head -1 $path | cut -d":" -f2) #Je recupère le nombre de lignes du header
		w=$(cat "$path" | wc -l) #Nbre de ligne total de l'archive
		let body="$w"-"$header"+2 #Nombre de ligne du body
		contenu=$(cat "$path" | tail -"$body") #Récupération du body
		fichier1=$1
		nomfich=$(echo "$fichier1" | rev | cut -d"\\" -f1 | rev) #Récuperer nom fichier entré par l'utilisateur
		occurence=$(grep -c $nomfich $path) # Chercher si le fichier existe dans l'archive
		taille=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f3) #Récuperer la taille du fichier
		type=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f2) #Récuperer le type (si fich ou doss)
		if [[ "$taille" -eq 0 ]]
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
			else #Arbo existe et à partir de là, les conditions sont vérifiées
				 bodycommence=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f4) #Recuperer la ligne ou le contenu commence
				 bodyetendre=$(cat "$path" | grep "^"$nomfich"" | awk '{print $5}') #Recuperer pour la ligne le nombre de ligne du body
				 bodyetendre=$((bodycommence-1+bodyetendre)) #Recuperer jusqu'où le contenu s'etendre
				 afficher=$(echo "$contenu" | sed -n "$bodycommence,$bodyetendre p") # J'affiche le contenu du fichier
				 echo "Voici l'archive souhaitée"
				 echo -e "\n"
				 echo "$afficher"
			fi
		fi
	elif [ $# -eq 2 ]
	then
		fichier1=$1
		fichier2=$2
                header=$(head -1 $path | cut -d":" -f2) #Je recupère le nombre de lignes du header
		w=$(cat "$path" | wc -l) #Nbre de ligne total de l'archive
		let body="$w"-"$header"+2 #Nombre de ligne du body
		contenu=$(cat "$path" | tail -"$body") #Récupération du body
		nomfich=$(echo "$fichier1" | rev | cut -d"\\" -f1 | rev) #Récuperer nom fichier entré par l'utilisateur
		nomfich2=$(echo "$fichier2" | rev | cut -d"\\" -f1 | rev) #Récuperer nom fichier entré par l'utilisateuer
		occurence=$(grep -c $nomfich $path) # Chercher si le fichier existe dans l'archive
		occurencefich2=$(grep -c $nomfich2 $path) #Chercher si le fichier 2 existe dans l'archive
		taille=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f3) #Récuperer la taille du fichier
		taille2=$(cat "$path" | grep "^"$nomfich2"" | cut -d" " -f3)
		type=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f2) #Récuperer le type (si fich ou doss)
		type2=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f2)
		if [[ "$taille" -eq 0 ]] && [["$taille2" -eq 0 ]]
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
			replace2=$(echo "$arbo" | sed 's/\\/\\\\/g')
			occurence2=$(grep -c $replace $path) #Occurence de l'arbo ?
			occurence3=$(grep -c $replace $path)
			if [[ $occurence2 -eq 0 ]] && [[ $occurence3 -eq 0 ]]
			then
				echo "Les Arbos existe pas"
				return
			else #Arbo existe et à partir de là, les conditions sont vérifiées
				 bodycommence=$(cat "$path" | grep "^"$nomfich"" | cut -d" " -f4) #Recuperer la ligne ou le contenu commence
				 bodycommence2=$(cat "$path" | grep "^"$nomfich2"" | cut -d" " -f4)
				 bodyetendre=$(cat "$path" | grep "^"$nomfich"" | awk '{print $5}') #Recuperer pour la ligne le nombre de ligne du body
				 bodyetendre2=$(cat "$path" | grep "^"$nomfich2"" | awk '{print $5}')
				 bodyetendre=$((bodycommence-1+bodyetendre)) #Recuperer jusqu'où le contenu s'etendre
				 bodyetendre2=$((bodycommence2-1+bodyetendre2))
				 afficher=$(echo "$contenu" | sed -n "$bodycommence,$bodyetendre p") # J'affiche le contenu du fichier
				 afficher2=$(echo "$contenu" | sed -n "$bodycommence2,$bodyetendre2 p")
				 echo "Voici les archives souhaitées"
				 echo "$afficher"
				 echo -e "\n"
				 echo "$afficher2"
			fi
		fi

	else
		echo "Erreur, aucun argument ou trop d'arguments"
		return
	fi
}
#Fonction pour dire que le serveur a pas comprit la commande
function commande-non-comprise() {
   echo "Le serveur ne peut pas interpréter cette commande"
}

# On accepte et traite les connexions

accept-loop