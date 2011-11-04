BINOMIAL_TABLE = "MU_RATE_CLASSES";
MU_RATE_TABLE = "SITE_MU_RATES";
NEB_TABLE = "SITE_POSTERIORS";
UPDATESQL = 1;

ExecuteAFile 					(HYPHY_LIB_DIRECTORY+"TemplateBatchFiles"+DIRECTORY_SEPARATOR+"Utility"+DIRECTORY_SEPARATOR+"GrabBag.bf");
ExecuteAFile 					(HYPHY_LIB_DIRECTORY+"TemplateBatchFiles"+DIRECTORY_SEPARATOR+"Utility"+DIRECTORY_SEPARATOR+"DBTools.ibf");
ExecuteAFile 					(HYPHY_LIB_DIRECTORY+"TemplateBatchFiles"+DIRECTORY_SEPARATOR+"Utility"+DIRECTORY_SEPARATOR+"DescriptiveStatistics.bf");
ExecuteAFile					(HYPHY_LIB_DIRECTORY+"TemplateBatchFiles"+DIRECTORY_SEPARATOR+"Utility"+DIRECTORY_SEPARATOR+"HXB2Mapper.bf");

binomialCoefficients = {};

SetDialogPrompt 		("454 run database file:");

ANALYSIS_DB_ID			= _openCacheDB ("");
DB_FILE_PATH 			= LAST_FILE_PATH;
haveTable				= _TableExists (ANALYSIS_DB_ID, "AA_ALIGNMENT");

fprintf					(stdout, "Minimum coverage required for analysis at a site:" );
fscanf					(stdin,"Number", coverageThreshold);

if ( DO_PIPELINE ) {
	fscanf					(stdin,"Number", _idx );
}
else {
	ExecuteAFile	("../Shared/hiv_1_ref_sequences.ibf");
	ChoiceList		( _idx,"Choose a reference sequence",1,SKIP_NONE,RefSeqNames);
	dagene			= (RefSeqNames[_idx][0]^{{"HXB2_"}{""}})^{{"NL4_3"}{""}}; 
}

if (!haveTable)
{
	fprintf (stdout, "[ERROR: NO AA_ALIGNMENT TABLE IN ", DB_FILE_PATH, "]\n");
	return 0;
}

tableInfo = {};
tableInfo["NUM_RATES"] 	= "INTEGER";
tableInfo["RATE_CLASS"] = "INTEGER";
tableInfo["MU_RATE"] 	= "REAL";
tableInfo["WEIGHT"] 	= "REAL";
tableInfo["LOG_LK"] 	= "REAL";
tableInfo["AIC"] 		= "REAL";
_CheckDBID ( ANALYSIS_DB_ID, BINOMIAL_TABLE, tableInfo );


tableInfo = {};
tableInfo["SITE"]			= "INTEGER";
tableInfo["SITE_HXB2"]		= "INTEGER";
tableInfo["COVERAGE"]		= "INTEGER";
tableInfo["CONSENSUS"]		= "INTEGER";
tableInfo["ENTROPY"]		= "REAL";
tableInfo["MU"]				= "REAL";
tableInfo["MU_RNK_PRCNT"] 	= "REAL";
_CheckDBID ( ANALYSIS_DB_ID, MU_RATE_TABLE, tableInfo );

refAA      = _ExecuteSQL (ANALYSIS_DB_ID, "SELECT REFERENCE AS REF FROM SETTINGS");
_codonToAA = defineCodonToAA();
refAA      = translateCodonToAA ((refAA[0])["REF"],_codonToAA,0);
hxb2AA	   = translateCodonToAA(RefSeqs[_idx],_codonToAA,0);

mapper         = mapSequenceToHXB2Aux (refAA, hxb2AA, 1);
reverse_mapper = {};
for (k = 0; k < Rows (mapper); k = k+1)
{
	reverse_mapper[mapper[k]] = k;
}

/*fprintf ( stdout, reverse_mapper, "\n" );*/

sitesWithCoverage = _ExecuteSQL (ANALYSIS_DB_ID, "SELECT POSITION FROM AA_ALIGNMENT WHERE COVERAGE >= " + coverageThreshold);

if ( Abs ( sitesWithCoverage ) > 0 ) {
		
	keys = Rows (sitesWithCoverage);
	siteCount = Abs (sitesWithCoverage);
	
	for (k = 0; k < siteCount ; k = k+1)
	{
		newKey = _mapNumberToString (0+keys[k]);
		if (keys[k] != newKey)
		{
			sitesWithCoverage[newKey] = sitesWithCoverage[keys[k]];
			sitesWithCoverage - keys[k];
		}
	}
	/*fprintf ( stdout, sitesWithCoverage, "\n" );*/
	
	mutationRate 			 = {Abs(sitesWithCoverage),5}["_MATRIX_ELEMENT_ROW_"];
	
	counter					 = 0;
	sitesWithCoverage		 ["iterateList"][""];
	
	counts					 = {siteCount, 2};
	
	for (k = 0; k < siteCount ; k = k+1)
	{
		counts[k][0] = mutationRate[k][3]; /*total coverage at site*/
		counts[k][1] = mutationRate[k][3] - mutationRate[k][4]; /*total coverage - consensus aa */
	}
	
	
	/*fprintf ( stdout, counts, "\n" );*/
	
	global P_1 = 0.5;
	P_1 :< 1; P_1 :> 0;
	
	
	fprintf (stdout, "Estimating mutation rates\n");
	
	Optimize (resN, jointBinomialP (P_1));
	
	AIC = -resN[1][0]*2 + 2;
	
	fprintf (stdout, "Single rate = ", P_1, ", Log L = ", resN[1][0], ", AIC = ", AIC, "\n");
	
	if ( UPDATESQL ) {
		DoSQL ( ANALYSIS_DB_ID, "INSERT INTO " + BINOMIAL_TABLE + " VALUES ('1', '1', '" + P_1 + "', '1.0', '" + resN[1][0] + "', '" + AIC + "')", "" );
	}
	
	for (rateCount = 2; rateCount < 10; rateCount += 1)
	{
		thisRate = "P_" + rateCount;
		ExecuteCommands ("global `thisRate` = 0.1; `thisRate` :< 1; `thisRate` :> 0;");
		generate_gdd_freqs (rateCount, "freqs", "discard", "M", 0);
		
		parameterMx = {rateCount*2, 1};
		
		for (aRate = 0; aRate < rateCount; aRate += 1)
		{
			ExecuteCommands ("parameterMx[aRate*2] := P_" + (aRate+1) +";\n");
			ExecuteCommands ("parameterMx[aRate*2+1] := "+freqs[aRate]+";\n");
		}
		
		Optimize (res2, jointBinomialMulti (parameterMx));
		
		disAIC = -res2[1][0]*2 + 4*rateCount;
		
		fprintf (stdout, "\n", rateCount, " rates\n",
		"Log (L) = ", res2[1][0], " AIC = ", disAIC);
		
		for (aRate = 0; aRate < rateCount; aRate += 1)
		{
			fprintf (stdout, "\n\tClass ", aRate+1, ".",
			"\n\t\tRate   = ", Format(Eval("P_" + (aRate+1)),8,5),
			"\n\t\tWeight = ",Format(Eval(freqs[aRate]),8,5));
			
			if ( UPDATESQL ) {
				DoSQL ( ANALYSIS_DB_ID, "INSERT INTO " + BINOMIAL_TABLE + " VALUES ('" + rateCount + "', '" + (aRate + 1) + "', '" + Format(Eval("P_" + (aRate+1)),8,5) + "', '" + Format(Eval(freqs[aRate]),8,5) + "', '" + res2[1][0] + "', '" + disAIC + "')", "" );
			}
			
		}
		
		/*fprintf ( stdout, "\nrateCount = ", rateCount, "; disAIC = ", disAIC, "; AIC = ", AIC, "\n" );*/
		
		if (disAIC > AIC)
		{
			break;
		}
		AIC = disAIC;
		
	}
	
	fprintf (stdout, "\n\n");
	
	mutationRate			 = mutationRate % 0;
	
	ranks					 = rankMatrix (mutationRate[-1][0]);
	mutationRate			 = mutationRate["ranks[_MATRIX_ELEMENT_ROW_]"]["_MATRIX_ELEMENT_COLUMN_==0"];
	mutationRate			 = mutationRate % 1;
	
	mutationRates			 = {};
	factor					 = 100/(Abs(sitesWithCoverage)-1);
	
	for (k = 0; k < Rows (mutationRate); k = k+1)
	{
		mutationRates[mutationRate[k][1]] = Format(factor*mutationRate[k][0],4,2);
	}
	
	/*fprintf ( stdout,sitesWithCoverage, "\n" );*/
	
	sitesWithCoverage["updateSiteMutationRates"][""];
	
}

DoSQL ( SQL_CLOSE, "", ANALYSIS_DB_ID );


/*---------------------------------------------------------------------*/

function rankMatrix (matrix)
{
	lastValue				   			 = matrix[0];
	lastIndex				   			 = 0;
	matrix							 [0] = 0;
	
	sampleCount = Rows (matrix);
	
	for (_i = 1; _i < sampleCount; _i = _i+1)
	{
		if (lastValue != matrix[_i])
		{
			meanIndex = _i - lastIndex;
			lastValue = matrix[_i];
			if (meanIndex > 1)
			{
				meanIndex = (lastIndex + _i - 1) * meanIndex / (2 * meanIndex);
				for (_j = lastIndex; _j < _i; _j = _j + 1)
				{
					matrix[_j] = meanIndex;
				}
			}
			matrix[_i] = _i;
			lastIndex = _i;
		}
	}
	
	meanIndex = _i - lastIndex;
	if (meanIndex > 1)
	{
		meanIndex = (lastIndex + _i - 1) * meanIndex / (2 * meanIndex);
		for (_j = lastIndex; _j < _i; _j = _j + 1)
		{
			matrix[_j] = meanIndex;
		}
	}
	else
	{
		matrix[_i-1] = _i - 1;
	}
	return matrix;
}

/*---------------------------------------------------------------------*/
function updateSiteMutationRates (key,value)
{
	siteID = value["POSITION"];
	result = retriveAASpectrumForSite (siteID);
	if ( UPDATESQL ) {
		SQLString = "";
		SQLString * 128;
		SQLString * ( "INSERT INTO " + MU_RATE_TABLE + " VALUES ('" + (siteID) + "', '" + (reverse_mapper[0+siteID]) + "', '" + result[0] + "', '" ); 
		SQLString * ( "" + result[3] + "', '" + result[1] + "', '" + result[2] + "', '" + mutationRates[siteID] + "')" );
		SQLString * 0;
		
		/*fprintf ( stdout, SQLString, "\n" );*/
		
		DoSQL ( ANALYSIS_DB_ID, SQLString, "" );
	}
	return 0;
}

/*---------------------------------------------------------------------*/



function iterateList (key,value)
{
	siteID = value["POSITION"];
	result = retriveAASpectrumForSite (siteID);	
	mutationRate [counter][0] = result[2]; /*percent non-consensus at site*/
	mutationRate [counter][1] = 0 + siteID;
	mutationRate [counter][3] = result[0]; /*total coverage at site */
	mutationRate [counter][4] = result[3]; /*number of consesus aa at site*/
	
	/*fprintf ( stdout, mutationRate[counter][0], " ", mutationRate[counter][1], " ", mutationRate[counter][3], " ", mutationRate[counter][4], "\n" );*/
	
	counter = counter + 1;
	return 0;
}

/*---------------------------------------------------------------------*/

function merge (key,value)
{
	if (Abs(positionList[key])==0)
	{
		positionList[key] = value;
	}
	return 0;
}

/*---------------------------------------------------------------------*/

function entropyC (key, value)
{
	entropy = entropy - (0+value)/total * Log ((0+value)/total);
	return 0;
}

/*---------------------------------------------------------------------*/

function retriveAASpectrumForSite (site)
{
	spectrum  = _ExecuteSQL (ANALYSIS_DB_ID, "SELECT * FROM AA_ALIGNMENT WHERE POSITION = " + site);

	if (Abs(spectrum) == 0 )
	{
		return {};
	}
	return retriveAASpectrumForSiteAux (spectrum[0]);
}


/*---------------------------------------------------------------------*/

function retriveAASpectrumForSiteAux (spectrum)
{
	referenceAA   = _codonToAA[spectrum["REFERENCE"]];	
	consensusAA   = _codonToAA[spectrum["CONSENSUS"]];	
		
	total	  	  = 0 + spectrum["COVERAGE"];
	
	codons        = Rows (_codonToAA);
	byResidue     = {};
	consensus 	  = 0;
	entropy		  = 0;
	
	for (cc = 0; cc < 64; cc = cc+1)
	{
		_aa    = _codonToAA[codons[cc]];
	    _count = (0+spectrum[codons[cc]]);
	    if (_count > 0)
	    {
			byResidue [_aa] = byResidue [_aa] + _count;
			if (_aa == consensusAA)
			{
				consensus = consensus + _count;
			}
		}
	}
	
	if (Abs (byResidue))
	{
		byResidue ["entropyC"][""];
	}
	
	return {{total__,entropy__/Log(2),(total__-consensus__)/total__,consensus__}};
	/*         0            1                     2                     3 */
}


/*---------------------------------------------------------------------*/

function jointBinomialP (p)
{
	LL = 0;
	for (k = 0; k < Rows (counts); k += 1)
	{
		LL +=  binomialP (p, counts[k][0], counts[k][1]);
	}
	return LL;
}

/*---------------------------------------------------------------------*/

function jointBinomialMulti (mx)
{

	LL = 0;
	for (k = 0; k < Rows (counts); k += 1)
	{
		l1 = 0;
		for (part = 0; part < Rows(mx); part += 2)
		{
			l1 +=  Exp(binomialP (mx[part], counts[k][0], counts[k][1])) * mx[part+1];
		}
		LL += Log (l1);
	}
	return LL;
}

/*---------------------------------------------------------------------*/

function binomialP (p,n,k)
{
	if (p == 0)
	{
		if (k > 0)
		{
			return -1e100;
		}
		else
		{
			return 0;
		}
	}
	return computeABinomialCoefficient (n,k) + k*Log(p) + (n-k)*Log(1-p);
}

/*---------------------------------------------------------------------*/

function computeABinomialCoefficient (n,k)
{
	key = "" + n + ";" + k;
	if (binomialCoefficients[key] != 0)
	{
		return binomialCoefficients[key];
	}
	
	res = 0;
	res :< 1e300;
	for (_s = k; _s > 0; _s = _s-1)
	{
		res = res + Log (n / _s);
		n = n-1;
	}
	
	binomialCoefficients[key] = res;
	return res;
}
