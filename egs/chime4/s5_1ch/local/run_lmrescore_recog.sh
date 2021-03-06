#!/bin/bash

# Copyright 2015 University of Sheffield (Jon Barker, Ricard Marxer)
#                Inria (Emmanuel Vincent)
#                Mitsubishi Electric Research Labs (Shinji Watanabe)
#  Apache 2.0  (http://www.apache.org/licenses/LICENSE-2.0)

# Copyright 2015, Mitsubishi Electric Research Laboratories, MERL (Author: Takaaki Hori)

nj=12
stage=1
order=5
hidden=300
rnnweight=0.5
nbest=100
train=noisy
eval_flag=true # make it true when the evaluation data are released

. utils/parse_options.sh || exit 1;

. ./path.sh
. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

# This is a shell script, but it's recommended that you run the commands one by
# one by copying and pasting into the shell.

if [ $# -ne 2 ]; then
  printf "\nUSAGE: %s <enhancement method> <model dir>\n\n" `basename $0`
  echo "First argument specifies a unique name for different enhancement method"
  echo "Second argument specifies acoustic and language model directory"
  exit 1;
fi

# set language models
lm_suffix=${order}gkn_5k
rnnlm_suffix=rnnlm_5k_h${hidden}

# enhan data
enhan=$1
# set model directory
mdir=$2
srcdir=exp/tri4a_dnn_tr05_multi_${train}_smbr_i1lats

# check language models
if [ ! -d $mdir/data/lang ]; then
  echo "error, set $mdir correctly"
  exit 1;
fi

# preparation
dir=exp/tri4a_dnn_tr05_multi_${train}_smbr_lmrescore
mkdir -p $dir
# make a symbolic link to graph info
if [ ! -e $dir/graph_tgpr_5k ]; then
  if [ ! -e exp/tri4a_dnn_tr05_multi_${train}/graph_tgpr_5k ]; then
    echo "graph is missing, execute local/run_dnn.sh, correctly"
    exit 1;
  fi
  pushd . ; cd $dir
  ln -s ../tri4a_dnn_tr05_multi_${train}/graph_tgpr_5k .
  popd
fi

# rescore lattices by a high-order N-gram
if [ $stage -le 3 ]; then
  # check the best iteration
  if [ ! -f $srcdir/log/best_wer_$enhan ]; then
    echo "$0: error $srcdir/log/best_wer_$enhan not found. execute local/run_dnn.sh, first"
    exit 1;
  fi
  it=`cut -f 1 -d" " $srcdir/log/best_wer_$enhan | awk -F'[_]' '{print $1}'`
  # rescore lattices
  if $eval_flag; then
    tasks="dt05_simu dt05_real et05_simu et05_real"
  else
    tasks="dt05_simu dt05_real"
  fi
  for t in $tasks; do
    steps/lmrescore.sh --mode 3 \
      $mdir/data/lang_test_tgpr_5k \
      $mdir/data/lang_test_${lm_suffix} \
      data-fmllr-tri3b/${t}_$enhan \
      $srcdir/decode_tgpr_5k_${t}_${enhan}_it$it \
      $dir/decode_tgpr_5k_${t}_${enhan}_${lm_suffix}
  done
  # rescored results by high-order n-gram LM
  mkdir -p $dir/log
  local/chime4_calc_wers.sh $dir ${enhan}_${lm_suffix} $dir/graph_tgpr_5k \
      > $dir/best_wer_${enhan}_${lm_suffix}.result
  head -n 15 $dir/best_wer_${enhan}_${lm_suffix}.result
fi

# N-best rescoring using a RNNLM
if [ $stage -le 4 ]; then
  # check the best lmw
  if [ ! -f $dir/log/best_wer_${enhan}_${lm_suffix} ]; then
    echo "error, rescoring with a high-order n-gram seems to be failed"
    exit 1;
  fi
  lmw=`cut -f 1 -d" " $dir/log/best_wer_${enhan}_${lm_suffix} | awk -F'[_]' '{print $NF}'`
  # rescore n-best list for all sets
  if $eval_flag; then
    tasks="dt05_simu dt05_real et05_simu et05_real"
  else
    tasks="dt05_simu dt05_real"
  fi
  for t in $tasks; do
    steps/rnnlmrescore.sh --inv-acwt $lmw --N $nbest --use-phi true \
      $rnnweight \
      $mdir/data/lang_test_${lm_suffix} \
      $mdir/data/lang_test_${rnnlm_suffix} \
      data-fmllr-tri3b/${t}_$enhan \
      $dir/decode_tgpr_5k_${t}_${enhan}_${lm_suffix} \
      $dir/decode_tgpr_5k_${t}_${enhan}_${rnnlm_suffix}_w${rnnweight}_n${nbest}
  done
  # calc wers for RNNLM results
  local/chime4_calc_wers.sh $dir ${enhan}_${rnnlm_suffix}_w${rnnweight}_n${nbest} $dir/graph_tgpr_5k \
      > $dir/best_wer_${enhan}_${rnnlm_suffix}_w${rnnweight}_n${nbest}.result
  head -n 15 $dir/best_wer_${enhan}_${rnnlm_suffix}_w${rnnweight}_n${nbest}.result
fi
