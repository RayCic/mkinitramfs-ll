#!/bin/zsh
# $Id: mkinitramfs-ll/svc/sdr.zsh,v 0.13.0 2014/08/08 12:59:45 -tclover Exp $
basename=${(%):-%1x}

# @FUNCTION: usage
# @DESCRIPTION: print usages message
usage() {
  cat <<-EOF
  $basename-0.13.0
  usage: $basename [-update|-remove] [-r|-squashroot<dir>] -d|-squashdir:<dir>:<dir>

  -q, -squashroot<dir>    overide default value of squashed rootdir 'squashdirir=/var/aufs'
  -d, -squashdir<dir>     squash colon seperated list of dir
  -f, -fstab              whether to write the necessary mount lines to '/etc/fstab'
  -b, -bsize131072        use [128k] 131072 bytes block size, which is the default
  -x, -busyboxbusybox     path to a static busybox binary, default is \$(which bb)
  -c, -com'gzip'          use lzo compressor with compression option, default to lzo
  -e, -exclude:<dir>      collon separated list of directories to exlude from image
  -o, -offset0            overide default [10%] offset used to rebuild squashed dir
  -u, -update             update the underlying source directory e.g. bin:sbin:lib32
  -r, -remove             remove the underlying source directory e.g. usr:\${PORTDIR}
  -n, -nomount            do not remount squashed dir nor aufs after rebuilding 
  -h, -help               print this help/usage and exit

 usage: AUFS+squahfs or *squash* and remove underlying src directories:
 $basename -r -d/var/db:/var/cache/edb:\$PORTDIR:/var/lib/layman
 usage: squash system related directories and update the underlaying src dir:
 $basename -u -d/bin:/sbin:/lib32:/lib64:/usr
EOF
exit $?
}

# @VARIABLE: opts [associative array]
# @DESCRIPTION: declare if not declared while arsing options,
# hold almost every single option/variable

if [[ $# == 0 ]] || [[ -n ${(k)opts[-h]} ]] || [[ -n ${(k)opts[-help]} ]] { usage }
zmodload zsh/zutil
zparseopts -E -D -K -A opts q: squashroot: d: squashdir: f fstab b: bsize: \
	n nomount x:: busybox:: c: comp: e: excl: o: offset: u update r remove \
	h help || usage

# @VARIABLE: opts[-arc]
# @DESCRIPTION: LONG_BIT, word length, supported
opts[-arc]=$(getconf LONG_BIT)
# @VARIABLE: opts[-squashroot] | opts[-q]
# @DESCRIPTION: root of squashed dir
:	${opts[-squashroot]:=${opts[-r]:-/aufs}}
# @VARIABLE: opts[-offset] | opts[-o]
# @DESCRIPTION: offset or rw/rr or ro branch ratio
:	${opts[-offset]:=$opts[-o]}
# @VARIABLE: opts[-exclude] | opts[-e]
# @DESCRIPTION: colon separated list of excluded dir
:	${opts[-exclude]:=$opts[-e]}
# @VARIABLE: opts[-bsize] | opts[-b]
# @DESCRIPTION: Block SIZE of squashfs underlying filesystem block
:	${opts[-bsize]:=${opts[-b]:-131072}}
# @VARIABLE: opts[-comp] | opts[-c]
# @DESCRIPTION: COMPression command with optional option
:	${opts[-comp]:=${opts[-c]:-lzo -Xcompression-level 1}}
# @VARIABLE: opts[-busybox] | opts[-b]
# @DESCRIPTION: full path to a static busysbox binary needed for updtating 
# system wide dir
:	${opts[-busybox]:=${opts[-x]:-$(which bb)}}

# @FUNCTION: info
# @DESCRIPTION: print info message to stdout
info() { print -P " %B%F{green}*%b%f $@" }
# @FUNCTION: error
# @DESCRIPTION: print error message to stdout
error() { print -P " %B%F{red}*%b%f $@" }
# @FUNCTION: die
# @DESCRIPTION: call error() to print error message before exiting
die() {
	local ret=$?
	error $@
	return $ret
}
alias die='die "%F{yellow}%1x:%U${(%):-%I}%u:%f" $@'

setopt NULL_GLOB

# @FUNCTION: squashmount
# @DESCRIPTION: mount squashed dir
squashmount() {
	if [[ ${dir} == /*bin ]] || [[ ${dir} == /lib* ]] {
		local busybox=/tmp/busybox cp grep mount mv rm mcdir mrc mkdir
		cp ${opts[-busybox]} /tmp/busybox ||
			die "no static busybox binary found"
		cp="$busybox cp -ar"
		mv="$busybox mv"
		rm="$busybox rm -fr"
		mount="$busybox mount"
		umount="$busybox umount"
		grep="$busybox grep"
		mkdir="$busybox mkdir -p"
	} else {
		cp="cp -ar"; grep=grep
		mount=mount; umount=umount
		mv=mv; rm="rm -fr"
		mkdir="mkdir -p"
	}
	if ${=grep} -q aufs:${dir} /proc/mounts; then
		${=umount} -l ${dir} || die "$sdr: failed to umount aufs:${dir}"
	fi
	if ${=grep} -q ${base}/rr /proc/mounts; then
		${=umount} -l ${base}/rr || die "sdr: failed to umount ${base}.squashfs" 
	fi
	${=rm} ${base}/rw/* || die "sdr: failed to clean up ${base}/rw"
	[[ -f ${base}.squashfs ]] && ${=rm} ${base}.squashfs 
	${=mv} ${base}.tmp.squashfs ${base}.squashfs ||
	die "sdr: failed to move ${base}.tmp.squashfs"
	${=mount} -t squashfs -onodev,loop,ro ${base}.squashfs ${base}/rr &&
	{	
		if [[ -n ${(k)opts[-r]} ]] || [[ -n ${(k)opts[-remove]} ]] { 
			${=rm} ${dir} && ${=mkdir} ${dir} ||
			die "sdr: failed to clean up ${dir}"
		} 
		if [[ -n ${(k)opts[-u]} ]] || [[ -n ${(k)opts[-update]} ]] { 
			${=rm} ${dir} && ${=mkdir} ${dir} && ${=cp} ${base}/rr /${dir} ||
			die "sdr: failed to update ${dir}"
		}
		${=mount} -t aufs -o nodev,udba=reval,br:${base}/rw:${base}/rr aufs:${dir} ${dir} ||
		die "sdr: failed to mount aufs:${dir}"
	} || die "sdr: failed to mount ${base}.squashfs"
}

# @FUNCTION: squashdir
# @DESCRIPTION: squash-dir
squashdir() {
    local n=/dev/null
	if [[ -n ${(k)opts[-f]} || -n ${(k)opts[-fstab]} ]] {
		echo "${base}.squashfs ${base}/rr squashfs nodev,loop,rr 0 0" >>/etc/fstab ||
			die "sdr: failed to write squasshfs fstab line"
		echo "${dir} ${dir} aufs nodev,udba=reval,br:${base}/rw:${base}/rr 0 0" >>/etc/fstab ||
			die "sdr: failed to write aufs fstab line" 
	}
	mkdir -p -m 0755 ${base}/{rr,rw} || die "sdr: failed to create ${dir}/{rr,rw}"
	mksquashfs ${dir} ${base}.tmp.squashfs -b ${opts[-bsize]} -comp ${=opts[-comp]} \
		${=opts[-exclude]:+-wildcards -regex -e ${(pws,:,)opts[-exclude]}} ||
		die "sdr: failed to build ${dir}.squashfs"
	if [[ ${dir} == /lib${opts[-arc]} ]] {
		# move rc-svcdir cachedir if mounted
		mkdir -p /var/{lib/init.d,cache/splash}
		if grep ${dir}/splash/cache /proc/mounts 1>${n} 2>&1; then
			mount --move ${dir}/splash/cache /var/cache/splash &&
				mcdir=yes || die "sdr: failed to move cachedir"
		fi
		if grep ${dir}/rc/init.d /proc/mounts 1>${n} 2>&1; then
			mount --move ${dir}/rc/init.d /var/lib/init.d &&
				mrc=yes || die "sdr: failed to move rc-svcdir"
		fi
	}
	if [[ -n ${(k)opts[-n]} ]] || [[ -n ${(k)opts[-nomount]} ]] { :;
	} else { squashmount }
	if [[ -n $mcdir ]] { 
		mount --move /var/cache/splash ${dir}/splash/cache ||
			die "sdr: failed to move back cachedir"
	}
	if [[ -n $mrc ]] { 
		mount --move /var/lib/init.d ${dir}/rc/init.d ||
			die "sdr: failed to move back rc-svcdir"
	}
	info ">>> sdr:...squashed ${dir} sucessfully [re]build"
}

# @FUNCTION: squash_init
# @DESCRIPTION: initialize aufs+squashfs if need be, or exit if no support found
squash_init() {
	local n=/dev/null

	grep -q aufs /proc/filesystems ||
	if ! grep -q aufs /proc/modules; then
	    if ! modprobe aufs >${n} 2>&1; then
	        error "failed to initialize aufs kernel module, exiting"
	        opts[-nomount]=1
	    fi
	fi

    grep -q squashfs /proc/filesystems ||
	if ! grep -q squashfs /proc/modules; then
	    if ! modprobe squashfs >${n} 2>&1; then
	        die "failed to initialize squashfs kernel module, exiting"
	    fi
	fi
}
squash_init

for dir (${(pws,:,)opts[-squashdir]} ${(pws,:,)opts[-d]}) {
	base=${opts[-squashroot]}/${dir}
	base=${base//\/\//\/}
	if [[ -e ${opts[-squashroot]}/${dir}.squashfs ]] { 
		if [[ ${opts[-offset]:-10} != 0 ]] {
			r=${$(du -sk ${base}/rr)[1]}
			w=${$(du -sk ${base}/rw)[1]}
			if (( ($w*100/$r) < ${opts[-offset]:-10} )) { 
				info "sdr: skiping... ${dir}, or append -o|-offset option"
			} else {
				info ">>> sdr: updating squashed ${dir}..."
				squashdir
			}
		} else {
			info ">>> sdr: updating squashed ${dir}..."
			squashdir
		}
	} else {
		info ">>> sdr: building squashed ${dir}..."
		squashdir
	}
}

[[ -f $busybox ]] && rm -f $busybox
unset base dir opts rr rw

# vim:fenc=utf-8:ci:pi:sts=0:sw=4:ts=4:
