#!/bin/bash
# !!! IN PROGRESS !!!
# Script to save and purge docker container.
#
# TODO:
#  * purge archives
#  * save dir as parameter
#  * keep duration as parameter
#  * cleanup, comments and refactoring
#  * other stuff
#

# GZip compression between 1 (fastest) and 9 (best) - default: 6
[[ $1 =~ ^[1-9]$ ]] && COMPRESSION="$1" || COMPRESSION="6"

function generic_image_name()
{
	echo $(echo $1 | cut -d' ' -f1 | cut -d'.' -f2,3)
}

function format_date()
{
	echo ${1:0:4}-${1:4:2}-${1:6:2} ${1:8:2}:${1:10:2}
}

DATE=`date '+%Y%m%d%H%M'`
LOG=${DIRSAVE}/log/${DATE}.log

running_containers=`docker ps`
containers_id=($(echo "$running_containers" | awk 'NR>1 {print $1}'))
containers_image=($(echo "$running_containers" | awk 'NR>1 {print $2}'))

for image_name in ${containers_image[@]}
do
	image_name_formatted=`sed 's#/\|:#_#g' <<< "$image_name"`
	containers_image_formatted=("${containers_image_formatted[@]}" $image_name_formatted)
	echo "Image name $image_name formatted to $image_name_formatted."
done

for i in $(seq 0 $((${#containers_id[@]}-1)))
do
	new_image=save.${containers_image_formatted[$i]}.${containers_id[$i]}.$DATE
	tar_file=$DATE.${containers_image_formatted[$i]}.${containers_id[$i]}.tar
	echo "Docker commit container ID ${containers_id[$i]} to $new_image"
	docker commit -p ${containers_id[$i]} $new_image
	echo "Saving new image to $tar_file"
	docker save -o /save/$tar_file $new_image
	echo "Compressing TAR file with GZip (compression $COMPRESSION): $tar_file.gz"
	gzip -$COMPRESSION /save/$tar_file
done



docker_images=`docker images`
saved_images=($(echo "$docker_images" | awk 'NR>1 {if($1 ~ /^save\..+\.[0-9a-f]+\.[0-9]+$/) print $1 "." $3}'))
# echo "${saved_images[@]}"
# echo ${#saved_images[@]}

# Do not purge when there is only one backup
for ((i = 0; i < ${#saved_images[@]}; i++))
do
	names=("${names[@]}" "$(generic_image_name ${saved_images[$i]})")
done

single_images=($(printf '%s\n' "${names[@]}" | sort | uniq -u))

for ((i = 0; i < ${#saved_images[@]}; i++))
do
	image=$(generic_image_name ${saved_images[$i]})
	if [[ ! "${single_images[@]}" =~ "$image" ]]; then
		purgeable_images_tmp=("${purgeable_images_tmp[@]}" "${saved_images[$i]}")
		purgeable_images_generic_tmp=("${purgeable_images_generic_tmp[@]}" "$image")
	fi
done

purgeable_images_generic=($(printf '%s\n' "${purgeable_images_generic_tmp[@]}" | sort | uniq))
purgeable_images=($(printf '%s\n' "${purgeable_images_tmp[@]}" | sort))

for ((i = 0; i < ${#purgeable_images_generic[@]}; i++))
do
	for ((j = 0; j < ${#purgeable_images[@]}; j++))
	do
		if [[ ${purgeable_images[$j]} == save.${purgeable_images_generic[$i]}* ]]; then
			save_date=$(format_date $(cut -d'.' -f4 <<< "${purgeable_images[$j]}"))

			# > 0 means newer
			date_diff=$(( $(date --date="$save_date" +%s) - $(date --date="30 days ago" +%s) ))
			# TMP DEV
			# if [[ date_diff < 0 ]]; then
			if [[ date_diff > 0 ]]; then
				to_purge=("${to_purge[@]}" ${purgeable_images[$j]})
			fi
		fi
	done
done

printf '%s\n' "${to_purge[@]}"
for (( i = 0; i < ${#to_purge[@]}; i++ )); do
	image_id=$(cut -d. -f5 <<< ${to_purge[$i]})
	docker rmi $image_id
done


