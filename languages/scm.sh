# scheme payload compiler
# - add object files to payload_objs
# - add support libraries to payload_libs

# scm_debug=yes

dmsg_scm() 
{
  if [ ! "X$scm_debug" = X ]; then
    echo "SCM_DEBUG: $@"
  fi
}

scm_libs="liblambdanative libgambc"

compile_payload_scm()
{
  if [ -f "$appsrcdir/main.scm" ]; then
    echo " => compiling scheme payload.."
    # -------
    # add libraries as needed
    for scm_lib in $scm_libs; do
      if [ `string_contains " $payload_libs " " $scm_lib "` = no ]; then
         payload_libs="$payload_libs $scm_lib"
      fi
    done
    # -------
    # generate list of source (scheme) files
    scm_coremodules=" syntax-case config eventloop ln_core ln_glcore "
    scm_coresrcs=
    scm_auxsrcs=
    for m in $modules; do
      if [ $m = "syntax-case" ]; then
        scm_modsrc="$SYS_HOSTPREFIX/lib/syntax-case.scm"
      else
        scm_modsrc="$modsrc `locatefile modules/$m/$m.scm silent`"
      fi
      if [ `string_contains "$scm_coremodules" " $m "` = yes ]; then
        scm_coresrcs="$scm_coresrcs $scm_modsrc"
      else
        scm_auxsrcs="$scm_auxsrcs $scm_modsrc"
      fi
    done
    for p in $plugins; do
      scm_plugsrc="$scm_plugsrc `locatefile plugins/$p/$p.scm silent`"
      scm_auxsrcs="$scm_auxsrcs $scm_plugsrc"
    done
    scm_mainsrc=$appsrcdir/main.scm
    # note: textures, fonts and strings can't go before glcore!
    scm_srcs="$scm_coresrcs $texture_srcs $font_srcs $string_srcs $scm_auxsrcs $scm_mainsrc"
    dmsg_scm "scm_srcs=$scm_srcs"
    # -------
    # prep the compiler options
    if [ $SYS_MODE = "debug" ]; then
      scm_opts="(declare (block)(not safe)(standard-bindings)(extended-bindings)(debug)(debug-location))"
    else
      scm_opts="(declare (block)(not safe)(standard-bindings)(extended-bindings))"
    fi
    payload_cdefs="$payload_cdefs -D___SINGLE_HOST -D___LIBRARY -D___PRIMAL"
    if [ `is_standalone_app` = "yes" ]; then
       payload_cdefs="$payload_cdefs -DSTANDALONE"
    fi
    #--------
    # syntax-case special-case
    if [ `string_contains "$modules" "syntax-case"` = yes ]; then
      if [ ! -f ${SYS_HOSTPREFIX}/lib/gambcext.tmp ]; then
        echo " => compiling syntax-case dynamic library.."
        veval "$SYS_GSC -dynamic -o  ${SYS_HOSTPREFIX}/lib/gambcext.o1 ${SYS_HOSTPREFIX}/lib/syntax-case.scm"
        mv ${SYS_HOSTPREFIX}/lib/gambcext.o1 ${SYS_HOSTPREFIX}/lib/gambcext.tmp
      fi
      assertfile ${SYS_HOSTPREFIX}/lib/gambcext.tmp
      cp ${SYS_HOSTPREFIX}/lib/gambcext.tmp ${SYS_HOSTPREFIX}/lib/gambcext.o1
    else
      rmifexists ${SYS_HOSTPREFIX}/lib/gambcext.o1
    fi
    #--------
    # compile scheme source files
    mkdir -p "$SYS_PREFIX/build"
    scm_csrcs=
    scm_link_dirty=no
    for scm_src in $scm_srcs; do
      dmsg_scm "compiling $scm_src .."
      scm_path=`dirname $scm_src`
      scm_chsh=`stringhash "$scm_src"`
      scm_ctgt="$SYS_PREFIX/build/${scm_chsh}.c"
      scm_otgt="$SYS_PREFIX/build/${scm_chsh}.o"
      scm_dirty=no
      if [ ! -f $scm_otgt ] || [ ! -f $scm_ctgt ]; then
        scm_dirty=yes
      else
        scm_topdir=`dirname $scm_src`
        scm_topdir=`basename $scm_topdir`
        if [ "X$scm_topdir" = "Xtextures" ] || [ "X$scm_topdir" = "Xstrings" ] || [ "Xscm_$topdir" = "Xfonts" ]; then
          if [ `isnewer "$scm_src" "$scm_otgt"` = "yes" ]; then
            scm_dirty=yes
          fi
        else
          if [ `newersourceindir "$scm_src" "$scm_otgt"` = "yes" ]; then
            scm_dirty=yes
          fi
        fi
      fi
      if [ $scm_dirty = yes ]; then
        echo "    $scm_src .."
        scm_link_dirty=yes
        rmifexists "$scm_ctgt"
        veval "$SYS_GSC -prelude \"$scm_opts\" -c -o $scm_ctgt $scm_src"
        assertfile "$scm_ctgt"
        rmifexists "$scm_otgt"
        veval "$SYS_ENV $SYS_CC $payload_cdefs -c -o $scm_otgt $scm_ctgt -I$SYS_PREFIX/include -I$SYS_PREFIX/include/freetype2 -I$scm_path"
        assertfile "$scm_otgt"
      fi
      scm_csrcs="$scm_csrcs $scm_ctgt"
      payload_objs="$payload_objs $scm_otgt"
    done
    # -------
    # compile scheme linker file
    scm_lctgt=`echo "$scm_ctgt" | sed 's/\.c$/\_\.c/'`
    scm_lotgt=`echo "$scm_lctgt" | sed 's/c$/o/'`
    if [ $scm_link_dirty = yes ] || [ ! -f $scm_lotgt ]; then
      vecho "$SYS_GSC -link $scm_csrcs"
      scm_link_here=`pwd`
      cd `dirname $scm_lctgt`
      $SYS_GSC -link $scm_csrcs
      cd $scm_link_here
      assertfile $scm_lctgt
      veval "$SYS_ENV $SYS_CC $payload_cdefs -o $scm_lotgt -c $scm_lctgt -I$SYS_PREFIX/include"
    fi
    assertfile $scm_lotgt
    payload_objs="$payload_objs $scm_lotgt"
    # -------
    # compile scheme hook 
    scm_hctgt="$SYS_PREFIX/build/scm_hook.c"
    scm_hotgt=`echo "$scm_hctgt" | sed 's/c$/o/'`
    scm_hooksrc=`locatefile "languages/scm.c" silent`
    assertfile $scm_hooksrc
    scm_linker=`echo $scm_chsh"__"`
    cat $scm_hooksrc | sed "s|@SCM_LINKER@|$scm_linker|" > "$scm_hctgt"
    veval "$SYS_ENV $SYS_CC $payload_cdefs -o $scm_hotgt -c $scm_hctgt -I$SYS_PREFIX/include"
    payload_objs="$payload_objs $scm_hotgt"
    dmsg_scm "payload_objs = $payload_objs"
    dmsg_scm "payload_libs = $payload_libs"
    echo " => done compiling scheme payload"
  fi 
}

#eof
