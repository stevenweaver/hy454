ExecuteAFile 	(HYPHY_LIB_DIRECTORY+"TemplateBatchFiles"+DIRECTORY_SEPARATOR+"Utility"+DIRECTORY_SEPARATOR+"GrabBag.bf");
ExecuteAFile 	(HYPHY_LIB_DIRECTORY+"TemplateBatchFiles"+DIRECTORY_SEPARATOR+"Utility"+DIRECTORY_SEPARATOR+"DBTools.ibf");
ExecuteAFile 	(HYPHY_LIB_DIRECTORY+"TemplateBatchFiles"+DIRECTORY_SEPARATOR+"Utility"+DIRECTORY_SEPARATOR+"DescriptiveStatistics.bf");

ExecuteAFile					("../Shared/nucleotide_options.def");

AALetters						= "ACDEFGHIKLMNPQRSTVWY?-";
NucLetters						= "ACGT-N";
AAMap							= {};
for (k = 0; k < Abs (AALetters); k=k+1)
{
	AAMap[AALetters[k]] = k;
}

alignOptions = {};

SetDialogPrompt 		("454 run database file:");
ANALYSIS_DB_ID			= _openCacheDB ("");

DB_FILE_PATH 			= LAST_FILE_PATH;

ChoiceList	(whichTable,"Which table?", 1, SKIP_NONE, "Protein", "In-frame protein based reference", "Nucleotide", "Filtered nucleotide sequences");

if (whichTable < 0)
{
	return 0;
}

if (whichTable)
{
	tableName				= "NUC_ALIGNMENT";
}
else
{
	tableName				= "AA_ALIGNMENT";
}

haveTable				= _TableExists (ANALYSIS_DB_ID, tableName);


if (haveTable)
{
	max_position   = _ExecuteSQL (ANALYSIS_DB_ID, "SELECT MAX(POSITION) AS MX FROM " + tableName);
	max_position   = 0+(max_position[0])["MX"];

	ChoiceList	(filteringMethod,"Use query sequence?", 1, SKIP_NONE, "Yes", "Provide a sequence to determine coordinate range from", "No", "Input sequence coordinates directly");

	if (filteringMethod == 1)
	{
		fprintf ( stdout, "Window start:" );
		fscanf ( stdin, "Number", fromP );
		fprintf ( stdout, "Window end:" );
		fscanf ( stdin, "Number", toP );
		/*
		 fromP 		   = prompt_for_a_value 		  ("Starting position?",1,1,max_position-1,1);
		 toP 		   = prompt_for_a_value 		  ("Ending position?",1,fromP+1,max_position,1);
		 */
	}
	else
	{
		fprintf (stdout, "Filtering string: ");
		fscanf  (stdin,  "String", filterString);
		filterString = (filterString&&1)^{{"[^A-Z]"}{""}};
		if (whichTable == 1)
		{
			refStr		= ((_ExecuteSQL (ANALYSIS_DB_ID,"SELECT REFERENCE_PASS2 FROM SETTINGS"))[0])["REFERENCE_PASS2"];
		}
		else
		{
			settings 		= (_ExecuteSQL (ANALYSIS_DB_ID,"SELECT * FROM SETTINGS"))[0];
			ExecuteCommands ("_Genetic_Code = " + settings["GENETIC_CODE"]);
			ExecuteCommands (settings["OPTIONS"] ^ {{"_hyphyAssociativeArray","alignOptions_p2"}});
			codonToAAMap = makeAAMap();
			refStr		=  translateToAA(settings["REFERENCE"],0);

		}
		if (Abs (filterString))
		{
			inStr 		= {{refStr,filterString}};
			AlignSequences(aligned, inStr, alignOptions_p2);
			aligned	   = aligned[0];
			offsets    = computeCorrection (aligned[2]);
			offsets[1] = Abs(aligned[2])-offsets[1]-1;

			fromP = offsets[0] + 1;
			toP = offsets[0] + Abs(((aligned[1])[offsets[0]][offsets[1]])^{{"[^A-Z]",""}});
			fprintf (stdout, "\nUsing sequence determined range of ", fromP, " to ", toP, "\n");
		}
		else
		{
			fprintf (stdout, "ERROR: please feed me a meaningful string... [non empty, with letters in it]\n");
			return 0;
		}

	}

	if (whichTable)
	{
		rawSQL			  = "SELECT OFFSET, NUC_PASS2,REF_PASS2,OFFSET_PASS2 FROM SEQUENCES,SETTINGS WHERE OFFSET_PASS2 <= " + fromP + " AND SPAN_PASS2+OFFSET_PASS2 > " + toP;
	}
	else
	{
		rawSQL			  = "SELECT OFFSET, ALIGNED_AA,ALIGNED_AA_REF,ALIGNED FROM SEQUENCES,SETTINGS WHERE OFFSET <= " + fromP + " AND SPAN+OFFSET > " + toP*3 + " AND SCORE>THRESHOLD";
	}
	matchingSequences =  _ExecuteSQL (ANALYSIS_DB_ID, rawSQL);

	binner       = {};
	codon_binner = {};
	variantCount	   = Abs (matchingSequences);

	for (k = 0; k<variantCount; k=k+1)
	{
		if (whichTable)
		{
			qStr = (matchingSequences[k])["NUC_PASS2"];
			rStr = (matchingSequences[k])["REF_PASS2"];
			span = extractRegionBasedOnReference (rStr, fromP, toP, 0+(matchingSequences[k])["OFFSET_PASS2"]);
		}
		else
		{
			qStr = (matchingSequences[k])["ALIGNED_AA"];
			rStr = (matchingSequences[k])["ALIGNED_AA_REF"];
			cStr = (matchingSequences[k])["ALIGNED"];
			span = extractRegionBasedOnReference (rStr, fromP, toP, 1+(0+(matchingSequences[k])["OFFSET"])$3);
		}

		cStr2 = qStr[span[0]][span[1]];
		binner [cStr2] = binner[cStr2] + 1;
		/*isgaps 	= (cStr2 $ "^\\-+$")[0]>=0;
		 if (isgaps)
		 {
		 fprintf (stdout, ">ref\n",rStr, "\n>qry\n", qStr, "\n\n");
		 }*/
		if (whichTable == 0)
		{
			cStr2 				= cStr[3*span[0]][3*span[1]+2];
			codon_binner [cStr2] = codon_binner [cStr2] + 1;
		}
	}
	if (whichTable == 0)
	{
		binner = codon_binner;
	}
	totalVariants	   = Abs (binner);

	fprintf			   (stdout, "Found ", totalVariants, " variants among ", variantCount, " sequences\n");

	if (variantCount < presetTotalVariants)
	{
		_closeCacheDB			(ANALYSIS_DB_ID);
		maxDLB	= -1;
		return 0;
	}

	ChoiceList				(variantMethod,"Filter low frequency variants method", 1, SKIP_NONE, "Proportion", "Keep sequences representing a fixed proportion of the sample or greater",g
	"Counts", "Keep sequences representing with a minimum number of copies");


	if (variantMethod)
	{
		fprintf ( stdout, "Gate sequence variants at this copy number?" );
		fscanf ( stdin, "Number", threshold );
		/*threshold 		   = prompt_for_a_value 		  ("Gate sequence variants at this copy number?",0,0,variantCount,1);*/
	}
	else
	{
		fprintf ( stdout, "Gate sequence variants at this threshold?" );
		fscanf ( stdin, "Number", threshold );
		/*threshold 		   = prompt_for_a_value 		  ("Gate sequence variants at this threshold?",0.01,0,1,0);*/
		threshold		   = (variantCount*threshold+0.5)$1;

	}

	fprintf			     (stdout, "Excluding all variants with fewer than ", threshold, " copies\n");
	retained		   = {};
	variants		   = Rows (binner);
	threshold		   = Max(threshold, minCopyCount);
	for (k = 0; k < totalVariants; k = k+1)
	{
		seq = variants[k];
		if (binner[seq] >= threshold)
		{
			retained [k] = binner[seq];
		}
	}
	retainedVariants = Abs (retained);
	retainedIndices	 = Rows (retained);
	toSort = {retainedVariants,2};
	for (k = 0; k < retainedVariants; k=k+1)
	{
		toSort [k][0] = 0+retainedIndices[k];
		toSort [k][1] = retained[retainedIndices[k]];
	}
	toSort = toSort%1;

	ChoiceList		(clones,"Include clonal sequences?", 1, SKIP_NONE, "Yes", "Include existing clones", "No", "Do not include clonal sequences");
	if (clones == 0)
	{
		SetDialogPrompt ("Read clones from:");
		fscanf (PROMPT_FOR_FILE, "Raw", cloneSeqs);
	}

	fprintf 		(stdout, "Retained ", retainedVariants, " variants\n\n");
	SetDialogPrompt ("Save filtered variants to:");

	mleEst = 0;
	if (retainedVariants < 2)
	{
		_closeCacheDB			(ANALYSIS_DB_ID);
		maxDLB	= -2;
		return 0;
	}


	fprintf (PROMPT_FOR_FILE, CLEAR_FILE, KEEP_OPEN);

	for (k = retainedVariants-1; k>=0; k=k-1)
	{
		fprintf (LAST_FILE_PATH, ">variant_",(retainedVariants-k),"_",toSort[k][1],"_copies\n", ((variants[toSort[k][0]])^{{"-"}{""}}), "\n");	g
	}

	if (clones == 0)
	{
		fprintf (LAST_FILE_PATH, cloneSeqs);
	}

	fprintf (LAST_FILE_PATH,CLOSE_FILE);
	inFile = LAST_FILE_PATH;

	/*check for frameshifts in longest read before alignment */
	ApplyGeneticCodeTable (geneticCodeTable);
	codonToAAMap = makeAAMap();
	DataSet testDS = ReadDataFile ( inFile );
	DataSetFilter testFilter = CreateFilter ( testDS, 1 );
	GetInformation (testSequences,testFilter );
	GetString ( testNames,testFilter,-1);

	seqLengthNameAVL = {};
	seqLengthArray = { Columns ( testSequences ), 2 };

	testlongestSequence = 0;
	for ( ts = 0; ts < Columns ( testSequences ); ts = ts + 1 ) {

		testSequences[ts] = ((testSequences[ts]^{{"[^a-zA-Z]",""}})^{{"^N+",""}})^{{"N+$",""}};

		if ( Abs ( testSequences[ts] ) > testlongestSequence ) {
			testlongestSequence = Abs ( testSequences[ts] );
			testlongestSequenceIDX = ts;
		}

		seqLengthArray[ts][0] = ts;
		seqLengthArray[ts][1] = Abs ( testSequences[ts]);

		seqLengthNameAVL[ts]	= {};

		(seqLengthNameAVL[ts])["NAME"] = testNames [ ts ];
		(seqLengthNameAVL[ts])["LENGTH"] =  Abs ( testSequences[ts] );

		aSeq = testSequences[ts];

		minStops = 1e20;
		tString  = "";
		rFrame   = 0;

		stopPosn = {3,2};
		allTran  = {3,1};

		for (offset = 0; offset < 3; offset += 1)
		{
			translString = translateCodonToAA (aSeq, codonToAAMap, offset);
			stopPos = translString||"X";
			if (stopPos[0]>=0)
			{
				stopCount = Rows(stopPos)$2;
				stopPosn[offset][0] = stopPos[0];
				stopPosn[offset][1] = stopPos[stopCount*2-1];
			}
			else
			{
				stopCount = 0;
			}
			if (stopCount<minStops)
			{
				minStops = stopCount;
				rFrame   = offset;
				tString  = translString;
			}
			allTran[offset] = translString;
		}

		fprintf ( stdout, "\n" );

		if (minStops>0)
		{
			(seqLengthNameAVL[ts])["FS"] = 1;
		}
		else {
			(seqLengthNameAVL[ts])["FS"] = 0;
		}
	}

	seqLengthArray = (seqLengthArray % 1);

	gotReference = 0;
	checkFS = 0 + (seqLengthNameAVL[testlongestSequenceIDX])["FS"];

	if ( checkFS ) {
		seq_idx = Rows ( seqLengthArray ) - 2;
		while ( seq_idx >= 0 ) {
			real_idx = seqLengthArray[seq_idx][0];
			checkFS = 0 + (seqLengthNameAVL[real_idx])["FS"];
			if ( !checkFS ) {
				gotReference = 1;
				break;
			}
			else {
				seq_idx = seq_idx - 1;
			}
		}
		refName = testNames[seqLengthArray[seq_idx][0]];
		refSeq = testSequences[seqLengthArray[seq_idx][0]];
	}
	else {
		refName = testNames[testlongestSequenceIDX];
		refSeq = testSequences[testlongestSequenceIDX];
		gotReference = 1;
	}

	if ( gotReference ) {
		fprintf ( inFile, CLEAR_FILE, ">", refName, "\n", refSeq, "\n" );
		for ( k = 0; k < Columns ( testSequences ); k = k + 1 ) {
			if ( testNames [ k ] != refName ) {
				fprintf ( inFile, ">", testNames[k], "\n", testSequences[k], "\n" );
			}
		}
		alignOptions2 = {};
		alignOptions2["0"] = aaScoreString;
		alignOptions2["1"] = "No penalty";
		alignOptions2["2"] = "First in file";
		alignOptions2["3"] = "No";
		alignOptions2["4"] = inFile;
		alignOptions2["5"] = "Yes";
		alignOptions2["6"] = "No";
		alignOptions2["7"] = inFile + ".fas";
		ExecuteAFile ("../Shared/SeqAlignment.bf", alignOptions2);
		WARN_NUC_ALIGN = 0;

		/*check the aligned sequences for indel errors. when reading frame shifts are not detected the 'No Penalty' option will make either the entire sequence or large proportion of sequence indels */
		doNucAlignment = 0;
		readtest = inFile + ".fas.nuc";
		DataSet testDS2 = ReadDataFile ( readtest );
		DataSetFilter testFilter2 = CreateFilter ( testDS2, 1 );
		GetInformation (testSequences2,testFilter2 );
		for ( ts = 0; ts < Columns ( testSequences2 ); ts = ts + 1 )g
		{
			seq = testSequences2 [ ts ];
			indelPos = seq||"-";
			indelCount = Rows(indelPos)$2;
			indelProp = indelCount/Abs(seq);
			if ( indelProp > ALLOWED_INDEL_PROPORTION ) {
				doNucAlignment = 1;
				break;
			}
		}
	}
	else {
		doNucAlignment = 1;
	}
	if ( doNucAlignment ) {
		alignOptions = {};
		alignOptions ["0"] = "No penalty";
		alignOptions ["1"] = "First in file";
		alignOptions ["2"] = "No";
		alignOptions ["3"] = inFile;
		alignOptions ["4"] = "No";
		alignOptions ["5"] = inFile;
		ExecuteAFile ("../Shared/SeqAlignmentNuc.bf", alignOptions);
		WARN_NUC_ALIGN = 1;
	}

	if ( !WARN_NUC_ALIGN ) {
		tempFile = "";
		tempFile = inFile + ".fas.nuc";
		fscanf ( tempFile, "Raw", fileStringRaw );
		fprintf ( inFile, CLEAR_FILE, fileStringRaw );
	}

	njOptions = {};
	njOptions ["0"] = "Distance formulae";
	njOptions ["1"] = "Nucleotide/Protein";
	njOptions ["2"] = inFile;
	njOptions ["3"] = "Force Zero";
	njOptions ["4"] = "TN93";
	njOptions ["5"] = "y";
	njOptions ["6"] = inFile+".tree";
	ExecuteAFile (HYPHY_LIB_DIRECTORY + "TemplateBatchFiles" + DIRECTORY_SEPARATOR + "NeighborJoining.bf", njOptions);

	/* alignOptions = {};
	 alignOptions ["0"] = "100";
	 alignOptions ["1"] = inFile + ".bootraw";
	 alignOptions ["2"] = "Proportions";
	 alignOptions ["3"] = "70";
	 alignOptions ["4"] = inFile + ".njboot.ps";
	 ExecuteAFile (HYPHY_LIB_DIRECTORY + "TemplateBatchFiles" + DIRECTORY_SEPARATOR + "post_npbs.bf", alignOptions);	*/

	alignOptions = {};
	alignOptions ["0"] = inFile;
	alignOptions ["1"] = "HKY85";
	alignOptions ["2"] = "Global";
	alignOptions ["3"] = inFile+".tree";

	ExecuteAFile 			(HYPHY_LIB_DIRECTORY + "TemplateBatchFiles" + DIRECTORY_SEPARATOR + "AnalyzeNucProtData.bf", alignOptions); 
	fprintf (stdout,		 TipName (givenTree, -1),"\n\n");

	mleEst = maxPathInATree ("givenTree");

	if (mleEst < distanceThreshold)
	{
		_closeCacheDB			(ANALYSIS_DB_ID);
		maxDLB	= -2;
		return 0;
	}

	simFile = inFile+".sim";

	alignOptions ["0"] = simFile;
	alignOptions ["3"] = simFile+".tree";

	simD	= {replicateCount,1};

	njOptions = {};
	njOptions ["0"] = "Distance formulae";
	njOptions ["1"] = "Nucleotide/Protein";
	njOptions ["2"] = simFile;
	njOptions ["3"] = "Force Zero";
	njOptions ["4"] = "TN93";
	njOptions ["5"] = "y";
	njOptions ["6"] = alignOptions ["3"];

	fprintf (stdout, njOptions);

	if ( !MPI_NODE_COUNT ) {
		/* serial code*/
		for (replicate = 0; replicate < replicateCount; replicate = replicate + 1)
		{
			DataSetFilter simData 	= Bootstrap (filteredData,1);
			fprintf 				(simFile, CLEAR_FILE, simData);
			ExecuteAFile 			(HYPHY_LIB_DIRECTORY + "TemplateBatchFiles" + DIRECTORY_SEPARATOR + "NeighborJoining.bf", njOptions, "nj");
			ExecuteAFile 			(HYPHY_LIB_DIRECTORY + "TemplateBatchFiles" + DIRECTORY_SEPARATOR + "AnalyzeNucProtData.bf", alignOptions, "sim");
			simD [replicate] 		= maxPathInATree ("sim.givenTree");
		}
	}
	else {

		/*MPI code */
		MPINodeState	= {MPI_NODE_COUNT-1,2};
		received = 0;
		replicate = 0;
		while ( received < replicateCount ) {
			if ( replicate < replicateCount ) {
				for ( mpiNode = 0; mpiNode < MPI_NODE_COUNT-1; mpiNode = mpiNode + 1 ) {
					if ( MPINodeState[mpiNode][0] == 0 ) {
						break;
					}
				}
			}
			else {
				mpiNode = MPI_NODE_COUNT-1;
			}
			if ( mpiNode == MPI_NODE_COUNT-1 ) {
				fromNode = ReceiveJobs ( 1 );
				simD [received] = 0 + maxDist;
				received = received + 1;
			}
			else {

				mpiString = "";
				mpiString * 128;
				mpiString * ( "njOptions = " + njOptions + "; alignOptions = " + alignOptions + ";" );
				mpiString * ( "DataSet ds = ReadDataFile (\"" + inFile + "\");" );
				mpiString * ( "DataSetFilter filteredData = CreateFilter  (ds,1);" );g
				mpiString * ( "DataSetFilter simData = Bootstrap ( filteredData, 1 );" );
				mpiString * ( "simFile = \"" + inFile + "\" + \".\" + \"" + mpiNode + "\" + \".sim\";" );
				mpiString * ( "alignOptions[\"0\"] = simFile;" );
				mpiString * ( "alignOptions[\"3\"] = simFile+\".tree\";" );
				mpiString * ( "njOptions[\"2\"] = simFile;" );
				mpiString * ( "njOptions[\"6\"] = alignOptions[\"3\"];" );
				mpiString * ( "fprintf 				(simFile, CLEAR_FILE, simData);" );
				mpiString * ( "ExecuteAFile 			(HYPHY_LIB_DIRECTORY + \"TemplateBatchFiles\" + DIRECTORY_SEPARATOR + \"NeighborJoining.bf\", njOptions, \"nj\");" );
				mpiString * ( "ExecuteAFile 			(HYPHY_LIB_DIRECTORY + \"TemplateBatchFiles\" + DIRECTORY_SEPARATOR + \"AnalyzeNucProtData.bf\", alignOptions, \"sim\");" ); 
				mpiString * ( "returnVal = maxPathInATree (\"sim.givenTree\");" );
				mpiString * ( "resultString = \"\";" );
				mpiString * ( "resultString * 128;" );
				mpiString * ( "resultString * (\"maxDist = \" );" );
				mpiString * ( "resultString * ( \"\" + returnVal + \";\" );" );
				mpiString * ( "resultString * 0;" );
				mpiString * ( "return resultString;" );
				mpiString * 0;

				MPISend ( mpiNode+1, mpiString );
				MPINodeState[mpiNode][0] = 1;
				MPINodeState[mpiNode][1] = Time(0);
				replicate = replicate + 1;

			}
		}
	}

	simD  = simD % 0;

	fprintf ( stdout, "simD = ", simD, "\n" );

	simDS = GatherDescriptiveStats (simD);



	PrintDescriptiveStats ("Max distance estimate", simDS);
	_closeCacheDB			(ANALYSIS_DB_ID);

	maxDLB = simD[replicate$20];
	return maxDLB;

	TREE_OUTPUT_OPTIONS = {};
	TREE_OUTPUT_OPTIONS		["TREE_OUTPUT_XTRA_MARGIN"] = 10;
	TREE_OUTPUT_OPTIONS 	["TREE_OUTPUT_SYMBOLS"] = 1;
	TREE_OUTPUT_OPTIONS 	["TREE_OUTPUT_SYMBOL_SIZE"] = symsize;
	allBN = givenTree^0;

	for (k = 1; k < Abs(allBN); k=k+1)
	{
		if (Abs((allBN[k])["Children"]) == 0)
		{
			bn = (allBN[k])["Name"];
			TREE_OUTPUT_OPTIONS[bn] = {};
			is454 = (bn$"^variant\\_[0-9]+\\_([0-9]+)");
			(TREE_OUTPUT_OPTIONS[bn])["TREE_OUTPUT_BRANCH_COLOR"] = {{0.6,0.6,0.6}};
			if (is454[0] < 0)
			{
				(TREE_OUTPUT_OPTIONS[bn])["TREE_OUTPUT_BRANCH_LABEL"] = "0.2 0.2 1 setrgbcolor 0 -__FONT_SIZE__ 2 idiv rmoveto __FONT_SIZE__ 0 rlineto 0 __FONT_SIZE__ rlineto -__FONT_SIZE__ 0 rlineto stroke 0 0 0 setrgbcolor ";
			}
			else
			{
				diamMult = Max((4+Log((0+bn[is454[2]][is454[3]])/variantCount)),1);
				(TREE_OUTPUT_OPTIONS[bn])["TREE_OUTPUT_BRANCH_LABEL"] = "1 0.2 0.2 setrgbcolor currentpoint exch __FONT_SIZE__ " + diamMult + " mul 2 div add exch __FONT_SIZE__ 2 idiv " + diamMult + " mul  0 360 arc fill 0 0 0 setrgbcolor";
			}
		}
	}
	treeS = PSTreeString (givenTree,"EXPECTED_NUMBER_OF_SUBSTITUTIONS",{{300,300}});
	treeFile = inFile+".ps";
	fprintf (treeFile,CLEAR_FILE,treeS);g


}
else
{
	fprintf (stdout, "ERROR: NO NUC_ALIGNMENT TABLE IN THIS FILE. PLEASE RERUN 454.bf ON THE .FNA FILE");
	return 0;
}


/*-------------------------------------------------*/

function ReceiveJobs ( null )	/*Modified from NielsenYang.bf */
{

	MPIReceive (-1, fromNode, result_String);
	ExecuteCommands ( result_String );

	timer2     = MPINodeState[fromNode-1][1];
	MPINodeState[fromNode-1][0] = 0;
	MPINodeState[fromNode-1][1] = 0;

	return fromNode;
}

/*-------------------------------------------------*/

function extractAField (key, value)
{
	storageArray [Abs (storageArray)] = 0+value[FIELD_NAME];
	return 0;
}

/*-------------------------------------------------*/

function extractFrequencySpectrum (key, value)
{
	storageArray [Abs (storageArray)] = 0+value[FIELD_NAME];
	return 0;
}

/*-------------------------------------------------*/

function extractFrequencySpectrum ()
{
	max  = 0; ind  = 0;
	max2 = 0; ind2 = 0;
	cols = Columns (SQL_ROW_DATA);
	for (k = 0; k < cols; k=k+1)
	{
		v = 0 + SQL_ROW_DATA[k];
		if (v > max)
		{
			max2 = max; ind2 = ind;
			max = v;    ind = k;
		}
	}
	minorityResidues [Abs(minorityResidues)] = max2/max;
	majorityResidues [Abs(majorityResidues)] = max;
	return 0;
}

/*-------------------------------------------------*/

function printFrequencySpectrum (min_t)
{
	max  = 0; ind  = 0;
	max2 = 0; ind2 = 0;
	cols = Columns (SQL_ROW_DATA);
	for (k = 0; k < cols; k=k+1)
	{
		v = 0 + SQL_ROW_DATA[k];
		if (v > max)
		{
			max2 = max; ind2 = ind;
			max = v;    ind = k;
		}
	}
	/*
	 max2/max;
	 majorityResidues [Abs(majorityResidues)] = max;
	 */
	fprintf (stdout, idx_to_res[ind]);
	seq_maj * idx_to_res[ind];
	if (max2/max >= min_t)
	{
		fprintf (stdout, ":", idx_to_res[ind2], " (", max2/max*100,"%)");
		seq_min * idx_to_res[ind2];
	}
	else
	{
		seq_min * idx_to_res[ind];
	}
	fprintf (stdout, "\n");
	return 0;
}

/*-------------------------------------------------*/

function report_consensus (indel_rate)
{

	return 0;
}

/*-------------------------------------------------*/

function maxPathInATree (treeID)
{
	maxPath = 0;
	ExecuteCommands ("lc=TipCount(`treeID`);tn=TipName(`treeID`,-1)");

	if (lc == 2)
	{
		return BranchLength (givenTree,0);
	}

	for (l1 = 0; l1 < lc-1; l1 = l1+1)
	{
		for (l2 = l1+1; l2 < lc; l2 = l2+1)
		{
			ExecuteCommands ("bl=BranchLength(`treeID`,\""+tn[l1]+";"+tn[l2]+"\");");
			maxPath = Max(maxPath,bl);
		}
	}

	return maxPath;
}
