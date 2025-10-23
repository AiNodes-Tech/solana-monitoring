#!/bin/bash
# set -x # uncomment to enable debug

#####    Packages required: jq, bc, node_exporter
#####    Fetching data from Solana validators, and put to /var/lib/node_exporter/textfile_collector/sol.prom
#####    Forked from stakeconomy and fix and add SFDP tracking

#####    CONFIG    ##################################################################################################
metricsFile="/var/lib/node_exporter/textfile_collector/sol.prom"
configDir="$HOME/.config/solana"  # the directory for the config files, eg.: /home/user/.config/solana
##### optional:                   #
identityPubkey=""                 # identity pubkey for the validator, insert if autodiscovery fails
voteAccount=""                    # vote account address for the validator, specify if there are more than one or if autodiscovery fails
additionalInfo="on"               # set to 'on' for additional general metrics like balance on your vote and identity accounts, number of validator nodes, epoch number and percentage epoch elapsed
binDir=""                         # auto detection of the solana binary directory can fail or an alternative custom installation is preferred, in case insert like $HOME/solana/target/release
rpcURL="http://127.0.0.1:8899"    # default is localhost with port number autodiscovered, alternatively it can be specified like http://custom.rpc.com:port. For example https://solana-testnet-rpc.publicnode.com
format="SOL"                      # amounts shown in 'SOL' instead of lamports
check_dz_balance="off"
#####  END CONFIG  ##################################################################################################

if [ -n "$binDir" ]; then
   cli="${binDir}/solana"
else
   if [ -z $configDir ]; then
      echo "please configure the config directory"
      exit 1
   fi
   installDir="$(cat ${configDir}/install/config.yml | grep 'active_release_dir\:' | awk '{print $2}')/bin"
   if [ -n "$installDir" ]; then cli="${installDir}/solana"; else
      echo "please configure the cli manually or check the configDir setting"
      exit 1
   fi
fi

if [ -z $rpcURL ]; then
   rpcPort=$(ps aux | grep agave-validator | grep -Po "\-\-rpc\-port\s+\K[0-9]+")
   if [ -z $rpcPort ]; then
      echo "Could not find node rpc port. May be it stopped"
      status=4 #stopped
      echo "nodemonitor_status{pubkey=\"$identityPubkey\"} $status" > "$metricsFile"
      exit 1
   fi
   rpcURL="http://127.0.0.1:$rpcPort"
fi

noVoting=$(ps aux | grep agave-validator | grep -c "\-\-no\-voting")
if [ "$noVoting" -eq 0 ]; then
   if [ -z $identityPubkey ]; then identityPubkey=$($cli address --url $rpcURL); fi
   if [ -z $identityPubkey ]; then
      echo "auto-detection failed, please configure the identityPubkey in the script if not done"
      exit 1
   fi
   if [ -z $voteAccount ]; then voteAccount=$($cli validators --url $rpcURL --output json-compact | jq -r '.validators[] | select(.identityPubkey == '\"$identityPubkey\"') | .voteAccountPubkey'); fi
   if [ -z $voteAccount ]; then
      echo "please configure the vote account in the script or wait for availability upon starting the node"
      exit 1
   fi
fi

validatorBalance=$($cli balance $identityPubkey | grep -o '[0-9.]*')
validatorVoteBalance=$($cli balance $voteAccount | grep -o '[0-9.]*')
solanaPrice=$(curl -s 'https://api.binance.com/api/v3/ticker/price?symbol=SOLUSDT' | jq -r .price)
#Use if node hosts in USA
#solanaPrice=$(curl -s 'GET' 'https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd' -H 'accept: application/json' | jq -r .solana.usd)

validatorCheck=$($cli validators --url $rpcURL)
if [ $(grep -c $voteAccount <<<$validatorCheck) == 0 ]; then
   echo "validator not found in set"
   exit 1
fi

blockProduction=$($cli block-production --url $rpcURL --output json-compact 2>&- | grep -v Note:)
validatorBlockProduction=$(jq -r '.leaders[] | select(.identityPubkey == '\"$identityPubkey\"')' <<<$blockProduction)
validators=$($cli validators --url $rpcURL --output json-compact 2>&-)
validatorsWithRank=$(jq -r '.validators | sort_by(-.epochCredits, -.activatedStake) | to_entries | map(.value + {rank: (.key + 1)})' <<<$validators)
currentValidatorInfo=$(jq -r '.[] | select(.voteAccountPubkey == '\"$voteAccount\"')' <<<$validatorsWithRank)
delinquentValidatorInfo=$(jq -r '.[] | select(.voteAccountPubkey == '\"$voteAccount\"' and .delinquent == true)' <<<$validatorsWithRank)
topVoteValidator=$(jq -r '. | max_by(.epochCredits)' <<<$validatorsWithRank)
topVoteValidatorCredits=$(jq -r '.epochCredits' <<<$topVoteValidator)

#Grab on boarding number for testnet node in Solana foundation delegation program
sfdpInfo=$(curl -s https://api.solana.org/api/validators/$identityPubkey)
sfdpOnboardingNumber=$(jq -r '.onboardingNumber' <<< $sfdpInfo)
if [[ -z "$sfdpOnboardingNumber" || "$sfdpOnboardingNumber" == 'null' ]]; then sfdpOnboardingNumber=0; fi


metricsData=""
metricsData+="nodemonitor_top_vote_credits{pubkey=\"$identityPubkey\"} $topVoteValidatorCredits"$'\n'
metricsData+="nodemonitor_solanaPrice{pubkey=\"$identityPubkey\"} $solanaPrice"$'\n'
if [[ ((-n "$currentValidatorInfo" || "$delinquentValidatorInfo")) ]] || [[ ("$validatorBlockTimeTest" -eq "1") ]]; then
   status=1 #status 0=validating 1=up 2=error 3=delinquent 4=stopped
   blockHeight=$(jq -r '.slot' <<<$validatorBlockTime)
   blockHeightTime=$(jq -r '.timestamp' <<<$validatorBlockTime)
   if [ -n "$blockHeightTime" ]; then blockHeightFromNow=$(expr $(date +%s) - $blockHeightTime); fi
   if [ -n "$currentValidatorInfo" ]; then
      status=0
      activatedStake=$(jq -r '.activatedStake' <<<$currentValidatorInfo)
      credits=$(jq -r '.credits' <<<$currentValidatorInfo)
      version=$(jq -r '.version' <<<$currentValidatorInfo | sed 's/ /-/g')
      version2=${version//./}
      commission=$(jq -r '.commission' <<<$currentValidatorInfo)
      rootSlot=$(jq -r '.rootSlot' <<<$currentValidatorInfo)
      lastVote=$(jq -r '.lastVote' <<<$currentValidatorInfo)
      leaderSlots=$(jq -r '.leaderSlots' <<<$validatorBlockProduction)
      skippedSlots=$(jq -r '.skippedSlots' <<<$validatorBlockProduction)
      totalBlocksProduced=$(jq -r '.total_slots' <<<$blockProduction)
      totalSlotsSkipped=$(jq -r '.total_slots_skipped' <<<$blockProduction)
      if [ "$format" == "SOL" ]; then activatedStake=$(echo "scale=2 ; $activatedStake / 1000000000.0" | bc); fi
      if [ -n "$leaderSlots" ]; then pctSkipped=$(echo "scale=2 ; 100 * $skippedSlots / $leaderSlots" | bc); fi
      if [ -z "$leaderSlots" ]; then leaderSlots=0 skippedSlots=0 pctSkipped=0; fi
      if [ -n "$totalBlocksProduced" ]; then
         pctTotSkipped=$(echo "scale=2 ; 100 * $totalSlotsSkipped / $totalBlocksProduced" | bc)
         pctSkippedDelta=$(echo "scale=2 ; 100 * ($pctSkipped - $pctTotSkipped) / $pctTotSkipped" | bc)
      fi
      if [ -z "$pctTotSkipped" ]; then pctTotSkipped=0 pctSkippedDelta=0; fi
      totalActiveStake=$(jq -r '.totalActiveStake' <<<$validators)
      totalDelinquentStake=$(jq -r '.totalDelinquentStake' <<<$validators)
      pctTotDelinquent=$(echo "scale=2 ; 100 * $totalDelinquentStake / $totalActiveStake" | bc)
      versionActiveStake=$(jq -r '.stakeByVersion.'\"$version\"'.currentActiveStake' <<<$validators)
      stakeByVersion=$(jq -r '.stakeByVersion' <<<$validators)
      stakeByVersion=$(jq -r 'to_entries | map_values(.value + { version: .key })' <<<$stakeByVersion)
      nextVersionIndex=$(expr $(jq -r 'map(.version == '\"$version\"') | index(true)' <<<$stakeByVersion) + 1)
      stakeByVersion=$(jq '.['$nextVersionIndex':]' <<<$stakeByVersion)
      stakeNewerVersions=$(jq -s 'map(.[].currentActiveStake) | add' <<<$stakeByVersion)
      totalCurrentStake=$(jq -r '.totalCurrentStake' <<<$validators)
      pctVersionActive=$(echo "scale=2 ; 100 * $versionActiveStake / $totalCurrentStake" | bc)
      pctNewerVersions=$(echo "scale=2 ; 100 * $stakeNewerVersions / $totalCurrentStake" | bc)
      epochCredits=$(jq -r '.epochCredits' <<<$currentValidatorInfo)
      rank=$(jq -r '.rank' <<<$currentValidatorInfo)

      leaderSchedule=$($cli leader-schedule --url $rpcURL --output json-compact 2>&-)
      validatorLeaderSlots=$(jq -r '.leaderScheduleEntries[] | select(.leader == '\"$identityPubkey\"')' <<<$leaderSchedule)
      currentSlot=$($cli slot)
      nextValidatorSlot=$(jq --argjson currentSlot "$currentSlot" -r 'select(.slot > $currentSlot) | .slot' <<<$validatorLeaderSlots | head -n1)
      deltaSlots=$(($nextValidatorSlot - $currentSlot))
      deltaSeconds=$(echo "$deltaSlots * 0.4" | bc)
      now=$(date +%s)
      nextValidatorSlotTime=$((( now + ${deltaSeconds%.*}) * 1000 ))

      metricsData+="nodemonitor_leaderSlots{pubkey=\"$identityPubkey\"} $leaderSlots"$'\n'
      metricsData+="nodemonitor_rootSlot{pubkey=\"$identityPubkey\"} $rootSlot"$'\n'
      metricsData+="nodemonitor_lastVote{pubkey=\"$identityPubkey\"} $lastVote"$'\n'
      metricsData+="nodemonitor_skippedSlots{pubkey=\"$identityPubkey\"} $skippedSlots"$'\n'
      metricsData+="nodemonitor_pctSkipped{pubkey=\"$identityPubkey\"} $pctSkipped"$'\n'
      metricsData+="nodemonitor_pctTotSkipped{pubkey=\"$identityPubkey\"} $pctTotSkipped"$'\n'
      metricsData+="nodemonitor_pctSkippedDelta{pubkey=\"$identityPubkey\"} $pctSkippedDelta"$'\n'
      metricsData+="nodemonitor_pctTotDelinquent{pubkey=\"$identityPubkey\"} $pctTotDelinquent"$'\n'
      metricsData+="nodemonitor_version{pubkey=\"$identityPubkey\"} $version2"$'\n'
      metricsData+="nodemonitor_pctNewerVersions{pubkey=\"$identityPubkey\"} $pctNewerVersions"$'\n'
      metricsData+="nodemonitor_commission{pubkey=\"$identityPubkey\"} $commission"$'\n'
      metricsData+="nodemonitor_activatedStake{pubkey=\"$identityPubkey\"} $activatedStake"$'\n'
      metricsData+="nodemonitor_credits{pubkey=\"$identityPubkey\"} $credits"$'\n'
      metricsData+="nodemonitor_epoch_credits{pubkey=\"$identityPubkey\"} $epochCredits"$'\n'
      metricsData+="nodemonitor_rank{pubkey=\"$identityPubkey\"} $rank"$'\n'
      if [ -n "$nextValidatorSlotTime" ]; then
         metricsData+="nodemonitor_next_validator_slot{pubkey=\"$identityPubkey\"} $nextValidatorSlotTime"$'\n'
      fi
   else status=2; fi

   if [ "$additionalInfo" == "on" ]; then
      nodes=$($cli gossip --url $rpcURL | grep -Po "Nodes:\s+\K[0-9]+")
      epochInfo=$($cli epoch-info --url $rpcURL --output json-compact)
      epoch=$(jq -r '.epoch' <<<$epochInfo)
      tps=$(jq -r '.transactionCount' <<<$epochInfo)
      pctEpochElapsed=$(echo "scale=2 ; 100 * $(jq -r '.slotIndex' <<<$epochInfo) / $(jq -r '.slotsInEpoch' <<<$epochInfo)" | bc)
      validatorCredits=$($cli vote-account $voteAccount --url $rpcURL | grep credits/max | cut -d ":" -f 2 | awk 'NR==1{print $1}')
      validatorCreditsCurrent=$(echo $validatorCredits | cut -d "/" -f 1 | awk 'NR==1{print $1}')
      validatorCreditsMax=$(echo $validatorCredits | cut -d "/" -f 2 | awk 'NR==1{print $1}')
      TIME=$($cli epoch-info | grep "Epoch Completed Time" | cut -d "(" -f 2 | awk '{print $1,$2,$3,$4}')
      VAR1=$(echo $TIME | grep -oE '[0-9]+day' | grep -o -E '[0-9]+')
      VAR2=$(echo $TIME | grep -oE '[0-9]+h'   | grep -o -E '[0-9]+')
      VAR3=$(echo $TIME | grep -oE '[0-9]+m'   | grep -o -E '[0-9]+')
      VAR4=$(echo $TIME | grep -oE '[0-9]+s'   | grep -o -E '[0-9]+')

      if [ -z "$VAR1" ]; then VAR1=0; fi
      if [ -z "$VAR2" ]; then VAR2=0; fi
      if [ -z "$VAR3" ]; then VAR3=0; fi
      if [ -z "$VAR4" ]; then VAR4=0; fi

      epochEnds=$(TZ=$timezone date -d "$VAR1 days $VAR2 hours $VAR3 minutes $VAR4 seconds" +"%m/%d/%Y %H:%M")
      epochEnds=$(( $(TZ=$timezone date -d "$epochEnds" +%s) * 1000 ))
      pctVote=$(echo "scale=4; 100 - ($pctEpochElapsed - ($validatorCreditsCurrent / $validatorCreditsMax * 100))" | bc)
      validatorScore=$(echo "scale=4; ($validatorCreditsCurrent / $topVoteValidatorCredits * 100)" | bc)

      metricsData+="nodemonitor_validatorBalance{pubkey=\"$identityPubkey\"} $validatorBalance"$'\n'
      metricsData+="nodemonitor_validatorVoteBalance{pubkey=\"$identityPubkey\"} $validatorVoteBalance"$'\n'
      metricsData+="nodemonitor_nodes{pubkey=\"$identityPubkey\"} $nodes"$'\n'
      metricsData+="nodemonitor_epoch{pubkey=\"$identityPubkey\"} $epoch"$'\n'
      metricsData+="nodemonitor_pctEpochElapsed{pubkey=\"$identityPubkey\"} $pctEpochElapsed"$'\n'
      metricsData+="nodemonitor_validatorCreditsCurrent{pubkey=\"$identityPubkey\"} $validatorCreditsCurrent"$'\n'
      metricsData+="nodemonitor_validatorCreditsMax{pubkey=\"$identityPubkey\"} $validatorCreditsMax"$'\n'
      metricsData+="nodemonitor_epochEnds{pubkey=\"$identityPubkey\"} $epochEnds"$'\n'
      metricsData+="nodemonitor_tps{pubkey=\"$identityPubkey\"} $tps"$'\n'
      metricsData+="nodemonitor_pctVote{pubkey=\"$identityPubkey\"} $pctVote"$'\n'
      metricsData+="nodemonitor_validatorScore{pubkey=\"$identityPubkey\"} $validatorScore"$'\n'
      metricsData+="nodemonitor_sfdp_onboarding_number{pubkey=\"$identityPubkey\"} $sfdpOnboardingNumber"$'\n'
   fi

   if [ -n "$delinquentValidatorInfo" ]; then
      status=3
   fi
else
   status=2
fi

if [ "$check_dz_balance" == "on" ]; then
   dzAddress=$(doublezero address)
   dzBalance=$(doublezero-solana revenue-distribution fetch validator-deposits \
       -u mainnet-beta \
       --node-id $dzAddress \
      | awk -F'|' 'NR>2 && NF {gsub(/^[ \t]+|[ \t]+$/, "", $3); print $4}' | head -1)
   metricsData+="nodemonitor_dz_balance{pubkey=\"$identityPubkey\", dz_address=\"$dzAddress\"} $dzBalance"$'\n'
fi

metricsData+="nodemonitor_status{pubkey=\"$identityPubkey\", voteAccountPubkey=\"$voteAccount\"} $status"$'\n'
echo "$metricsData" > "$metricsFile"
