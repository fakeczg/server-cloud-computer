#!/bin/bash

if [ $# -lt 3 ]; then
	echo "Usage: $0 <cp|adb> <SRC> <DST> [p src|p dst]"
	echo "  <cp|adb>   : 'cp' for local copy or 'adb' for pushing to device"
	echo "  <SRC>      : Source directory or path"
	echo "  <DST>      : Destination directory or path"
	echo "  [p src]    : Optional. Print source file time information"
	echo "  [p dst]    : Optional. Print destination file time information"
	exit 1
fi

ACTION="$1"
SRC="$2"
DST="$3"

FILES=(
	"vendor/lib64/egl/libEGL_FTG340.so"
	"vendor/lib64/egl/libGLESv1_CM_FTG340.so"
	"vendor/lib64/egl/libGLESv2_FTG340.so"
	"vendor/lib64/hw/gralloc.FTG340.so"
	"vendor/lib64/hw/vulkan.FTG340.so"
	"vendor/lib64/libvulkan_FTG340.so"
	"vendor/lib64/libdrm_android.so"
	"vendor/lib64/libdrm_FTG340.so"
	"vendor/lib64/libdrm_ftg340.so"
	"vendor/lib64/libdrm_vivante.so"
	"vendor/lib64/libSPIRV_FTG340.so"
	"vendor/lib64/libSPIRV_viv.so"
	"vendor/lib64/libGAL.so"
	"vendor/lib64/libGLSLC.so"
	"vendor/lib64/libVSC.so"

	"vendor/lib/egl/libEGL_FTG340.so"
	"vendor/lib/egl/libGLESv1_CM_FTG340.so"
	"vendor/lib/egl/libGLESv2_FTG340.so"
	"vendor/lib/hw/gralloc.FTG340.so"
	"vendor/lib/hw/vulkan.FTG340.so"
	"vendor/lib/libvulkan_FTG340.so"
	"vendor/lib/libdrm_FTG340.so"
	"vendor/lib/libdrm_android.so"
	"vendor/lib/libdrm_ftg340.so"
	"vendor/lib/libdrm_vivante.so"
	"vendor/lib/libSPIRV_FTG340.so"
	"vendor/lib/libSPIRV_viv.so"
	"vendor/lib/libGAL.so"
	"vendor/lib/libGLSLC.so"
	"vendor/lib/libVSC.so"
)

print_file_time_info() {
	local file=$1
	if [ -f "$file" ]; then
		mod_time=$(stat --format='%y' "$file")
		echo -e "File: $file \t Modification Time: $mod_time"
	else
		echo "File $file does not exist."
	fi
}

print_src_time_info() {
	local dir=$1
	echo "Listing time information for files in source directory $dir:"
	for file in "${FILES[@]}"; do
		src_file="$dir/$file"
		print_file_time_info "$src_file"
	done
}

print_dst_time_info() {
	local dir=$1
	if [ "$ACTION" == "adb" ]; then
		echo "Listing time information for files in destination directory $dir on device:"
		for file in "${FILES[@]}"; do
			dst_file="$dir/$file"
			mod_time=$(adb shell "stat --format='%y' $dst_file 2>/dev/null")
			if [ $? -eq 0 ]; then
				echo -e "File: $dst_file \t Modification Time: $mod_time"
			else
				echo "File $dst_file does not exist on the device."
			fi
		done
	else
		echo "Listing time information for files in destination directory $dir:"
		for file in "${FILES[@]}"; do
			dst_file="$dir/$file"
			print_file_time_info "$dst_file"
		done
	fi
}

create_dst_dir() {
	local dir=$1
	if [ ! -d "$dir" ]; then
		echo "Directory $dir does not exist. Creating it..."
		mkdir -p "$dir"
	fi
}

copy_file() {
	local src_file=$1
	local dst_file=$2
	local tmp_file="/tmp/an_gpu_libs_tmp/$(basename "$file")"

	# 创建临时目录
	mkdir -p /tmp/an_gpu_libs_tmp

	if [ -f "$dst_file" ]; then
		echo "Deleting existing destination file with sudo: $dst_file"
		sudo rm -f "$dst_file"
	fi

	echo "Copying $src_file to temporary location $tmp_file"
	cp -p "$src_file" "$tmp_file"

	echo "Moving $tmp_file to final destination $dst_file with sudo"
	sudo mv "$tmp_file" "$dst_file"
}

push_file_to_device() {
	local src_file=$1
	local dst_file=$2
	echo "Checking if file $dst_file exists on device..."
	adb shell "[ -f $dst_file ] && echo 'File exists on device' || echo 'File does not exist on device'"

	echo "Deleting existing destination file on device: $dst_file"
	adb shell "rm -f $dst_file"

	echo "Pushing $src_file to device at $dst_file"
	adb push "$src_file" "$dst_file"
}

remount_partition() {
	local partition=$1
	echo "Checking and remounting $partition if necessary..."

	mount_status=$(adb shell mount | grep "$partition")
	if [[ "$mount_status" == *"ro,"* ]]; then
		echo "$partition is read-only, remounting as read-write..."
		adb shell "mount -o remount,rw $partition"
	else
		echo "$partition is already read-write."
	fi
}

do_sync() {
	# 单次同步：区分本机/设备
	if [ "$ACTION" == "adb" ]; then
		adb shell sync
	else
		sync
	fi
}

# 查看时间信息选项
if [ "$4" == "p" ] && [ "$5" == "src" ]; then
	print_src_time_info "$SRC"
	exit 0
elif [ "$4" == "p" ] && [ "$5" == "dst" ]; then
	print_dst_time_info "$DST"
	exit 0
fi

# 执行操作
adb root

if [ "$ACTION" == "adb" ]; then
	remount_partition "/"
	remount_partition "/vendor"
	remount_partition "/data"
fi

if [ "$ACTION" == "cp" ]; then
	for file in "${FILES[@]}"; do
		src="$SRC/$file"
		dst="$DST/$file"

		print_file_time_info "$src"

		dst_dir=$(dirname "$dst")
		create_dst_dir "$dst_dir"

		copy_file "$src" "$dst"
		#do_sync
	done

	# 清理临时中转目录
	rm -rf /tmp/an_gpu_libs_tmp
	do_sync

elif [ "$ACTION" == "adb" ]; then
	for file in "${FILES[@]}"; do
		src="$SRC/$file"
		dst="$DST/$file"

		print_file_time_info "$src"

		push_file_to_device "$src" "$dst"
		#do_sync
	done
	do_sync
else
	echo "Invalid action. Use 'cp' for local copy or 'adb' for pushing to device."
	exit 1
fi
