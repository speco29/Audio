#!/bin/bash
#########################################################################################
# I/P: Word lattices generated by the decoder
# O/P: Two lab dirs (lab_wd_level/ and lab_phn_level/ containing files with lab info 
#      and confidence scores at word and phone level respectively)
#
#     --Steps--
# (1) Outputs one big lab file with word-level info and confidence scores
# (2) Outputs one big lab file with phone-level info and confidence scores
# (3) Splits the phone-and-word-level big lab files into individual lab files
#     for each utterance
#########################################################################################

dbName=$1
num_free_CPUs=$2

rm -r $dbName;  mkdir $dbName;
touch $dbName/wd_lab.txt; touch $dbName/phn_lab.txt

for i in $(seq 1 $num_free_CPUs); do
  # (1) Output one big lab file with word-level info and confidence scores
  lattice-align-words data/lang_test_Wug/phones/word_boundary.int exp/$dbName/final.mdl \
     ark:"gunzip -c exp/$dbName/decode_test/lat.$i.gz |" ark:- | \
     lattice-to-ctm-conf --acoustic-scale=0.1 ark:- $dbName/$i.wd.ctm 
  ./utils/int2sym.pl -f 5 data/lang_test_Wug/words.txt $dbName/$i.wd.ctm >> $dbName/wd_lab.txt

  # (2) Output one big lab file with phone-level info and confidence scores
  lattice-to-phone-lattice exp/$dbName/final.mdl \
     ark:"gunzip -c exp/$dbName/decode_test/lat.$i.gz |" ark:- | lattice-align-phones exp/$dbName/final.mdl ark:- ark:- \
     | lattice-1best --acoustic-scale=0.1 ark:- ark:- | nbest-to-ctm ark:- $dbName/$i.1best-to-ctm
  ./utils/int2sym.pl -f 5 data/lang_test_Wug/phones.txt $dbName/$i.1best-to-ctm \
     > $dbName/$i.1best-to-ctm.txt

  lattice-to-post --acoustic-scale=0.1 ark:"gunzip -c exp/$dbName/decode_test/lat.$i.gz |" ark:- | \
     post-to-phone-post exp/$dbName/final.mdl ark:- ark,t:$dbName/$i.phones.post
  lattice-to-phone-lattice exp/$dbName/final.mdl ark:"gunzip -c exp/$dbName/decode_test/lat.$i.gz |" \
     ark:- | lattice-best-path --acoustic-scale=0.1 --word-symbol-table=data/lang_test_Wug/phones.txt ark:- \
     ark,t:$dbName/$i.hyp.tra ark:- | ali-to-phones --per-frame=true exp/$dbName/final.mdl ark:- ark,t:$dbName/$i.phones.tra  
  get-post-on-ali ark:$dbName/$i.phones.post ark:$dbName/$i.phones.tra ark,t:$dbName/$i.phones.conf

  perl create_phn_lab.pl $dbName $i

  cat $dbName/$i.1best-to-ctm.txt.conf >> $dbName/phn_lab.txt
done

# (3) Split the phone-and-word-level big lab files into individual lab files for each utterance
rm -r ../../data_for_TTS/lab_*_level/*
cut -f 1 data/test/wav.scp > utt_ids
for i in $(cat utt_ids); do 
  grep -w $i $dbName/wd_lab.txt  | awk '{print $3+$4 " " 125 " " $5 " " $6}' > ../../data_for_TTS/lab_wd_level/$i.lab
  grep -w $i $dbName/phn_lab.txt | cut -d ' ' -f 2-5 > ../../data_for_TTS/lab_phn_level/$i.lab

  grep -w "SIL" ../../data_for_TTS/lab_phn_level/$i.lab >> ../../data_for_TTS/lab_wd_level/$i.lab
  sort -n -k1   ../../data_for_TTS/lab_wd_level/$i.lab  >  temp
  mv temp ../../data_for_TTS/lab_wd_level/$i.lab 
done
rm utt_ids