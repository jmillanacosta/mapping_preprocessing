package org.bridgedb.sec2pri;

import javax.xml.parsers.DocumentBuilderFactory;  
import javax.xml.parsers.DocumentBuilder;

import org.bridgedb.DataSource;
import org.bridgedb.IDMapperException;
import org.bridgedb.Xref;
import org.bridgedb.bio.DataSourceTxt;
import org.bridgedb.rdb.construct.DBConnector;
import org.bridgedb.rdb.construct.DataDerby;
import org.bridgedb.rdb.construct.GdbConstruct;
import org.bridgedb.rdb.construct.GdbConstructImpl4;
import org.w3c.dom.Document;  
import org.w3c.dom.NodeList;  
import org.w3c.dom.Node;  
import org.w3c.dom.Element;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.sql.SQLException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;  
import java.util.zip.*;
import java.util.Enumeration;

public class XMLsec2pri  {
	public static String sourceName = "hmdb";
	public static String sourceIdCode = "Ch";
	public static String sourceSymbolCode = "O"; // for hmdb (in general for metabolites, there is no system code for metabollite name, for now it is considered O
	public static String priIdNode = "accession";
	public static String secIdNode = "secondary_accessions";
	public static String secIdNodeTag = "accession"; // if the node doesn't have any tag; args[5] = NA 
	public static String priSymbolNode = "name";
	public static String secSymbolNode = "synonyms";
	public static String secSymbolNodeTag = "synonym"; // if the node doesn't have any tag; args[8] = NA 
	//public static String idOrName = "id";
	public static String DbVersion = "1.0.0";
	public static String BridgeDbVersion = "3.0.13";
	private static DataSource dsId;
	private static DataSource dsSymbol;
	private static GdbConstruct newDb;
	
	public static void main(String args[]) throws IOException, IDMapperException, SQLException {
		try {
			//Assign the input argument to the corresponding variables
			XMLsec2pri.sourceName = args[0];
			XMLsec2pri.sourceIdCode = args[1];
			XMLsec2pri.sourceSymbolCode = args[2];
			XMLsec2pri.priIdNode = args[3];
			XMLsec2pri.secIdNode = args[4];
			XMLsec2pri.secIdNodeTag = args[5];
			XMLsec2pri.priSymbolNode = args[6];
			XMLsec2pri.secSymbolNode = args[7];
			XMLsec2pri.secSymbolNodeTag = args[8];
			
			//Create output bridge mapping file
			setupDatasources();
			File outputDir = new File("output");
			outputDir.mkdir();
			File outputFile = new File(outputDir, sourceName + ".bridge");

			try {
				createDb(outputFile);
				} catch (IDMapperException e1) {
					e1.printStackTrace();
					}
			
			//Create output tsv mapping files
			////primary ID
			List<List<String>> listOfpri = new ArrayList<>(); //list of primary IDs
			////Secondary to primary ID
			List<List<String>> listOfsec2pri = new ArrayList<>(); //list of the secondary to primary IDs
			////name to synonyms
			List<List<String>> listOfname2symbol = new ArrayList<>(); //list of the name to symbol 
			
			//create a constructor of file class and parsing an XML file
			//File inputDir = new File("input");
			//File file = new File(new FileReader(inputDir + "/" + sourceName + ".zip"));
			File file = new File("input/hmdb_metabolites_split.zip");
			try (ZipFile zipfile = new ZipFile(file)) {
				//get th.e Zip Entries using the entries() function
				Enumeration<? extends ZipEntry> entries
				= zipfile.entries();
				
				//create tsv file with all the ChEBI IDs
		        List<String> pri= new ArrayList<String>(); 
				pri.add("primaryID");
				pri.add("\n");
				//create tsv mapping file for sec2pri ID
		        List<String> sec2pri= new ArrayList<String>(); 
				sec2pri.add("primaryID");
				sec2pri.add(",");
				sec2pri.add("secondaryID");
				sec2pri.add("\n");
				//create tsv mapping file for name2symbols
		        List<String> name2synonym= new ArrayList<String>(); 
		        name2synonym.add("primaryID");
		        name2synonym.add("\t");
		        name2synonym.add("name");
		        name2synonym.add("\t");
		        name2synonym.add("synonym");
		        name2synonym.add("\n");

			    //create BridgeDb mapping file
				Map<Xref, Set<Xref>> map = new HashMap<Xref, Set<Xref>>();
				int counter = 0;
				int counter2 = 0;
				boolean finished = false;
				
				while (entries.hasMoreElements() && !finished) {
					//get the zip entry
					ZipEntry entry = entries.nextElement();
				
					if (!entry.isDirectory() && entry.getName() != "hmdb_metabolites.xml") {
						//an instance of factory that gives a document builder
						InputStream inputStream = zipfile.getInputStream(entry);
						DocumentBuilderFactory docBuilderFactory = DocumentBuilderFactory.newInstance();
						DocumentBuilder docBuilder = docBuilderFactory.newDocumentBuilder();
						Document document = docBuilder.parse(inputStream);
						document.getDocumentElement().normalize();
						
						//Accession primary ID
						NodeList priIdList = document.getElementsByTagName(XMLsec2pri.priIdNode);
						Element priId = (Element) priIdList.item(0); //assumption: there is only one primary id used by the database
						//Add the secondary IDs if there is any
						NodeList secIdList = document.getElementsByTagName(XMLsec2pri.secIdNode);
						if (priId != null && secIdList.getLength() != 0) {
							
							Xref priIdRef = new Xref(priId.getTextContent(), dsId);
							map.put(priIdRef, new HashSet<Xref>());
							
							pri.add(priId.getTextContent());
							//Add the list to list of primary id in tsv
							listOfpri.add(pri);
							pri = new ArrayList<>();
							
							if (!XMLsec2pri.secIdNodeTag.equalsIgnoreCase("NA")) { //when there is tag for the node
								for (int itr = 0; itr < secIdList.getLength(); itr++) {
									Node node = secIdList.item(itr);
									if (node.getNodeType() == Node.ELEMENT_NODE) {
										Element eElement = (Element) node;
										NodeList secIds = eElement.getElementsByTagName(XMLsec2pri.secIdNodeTag);
										for (int itr2 = 0; itr2 < secIds.getLength(); itr2++) {
											Element secId = (Element) secIds.item(itr2);
											Xref secIdRef = new Xref(secId.getTextContent(), dsId, false); //the first column is the secondary id so idPrimary = false
											map.get(priIdRef).add(secIdRef);
											
											sec2pri.add(priId.getTextContent());
											sec2pri.add(",");
											sec2pri.add(secId.getTextContent());

											//Add the list to list of list for the secondary to primary id mapping in tsv
											listOfsec2pri.add(sec2pri);
											sec2pri = new ArrayList<>();										
											}
										}
									}
								} else { //when there is no tag for the node
									Element secId = (Element) secIdList.item(0); //assumption: there is only one name used by the database
									Xref secIdRef = new Xref(secId.getTextContent(), dsId);
									map.get(priIdRef).add(secIdRef);
									
									sec2pri.add(priId.getTextContent());
									sec2pri.add(",");
									sec2pri.add(secId.getTextContent());

									//Add the list to list of list for the secondary to primary id mapping in tsv
									listOfsec2pri.add(sec2pri);
									sec2pri = new ArrayList<>();
									}
							//Add the primary Symbol
							NodeList priSymbolList = document.getElementsByTagName(XMLsec2pri.priSymbolNode);
							Element priSymbol = (Element) priSymbolList.item(0); //assumption: there is only one primary name used by the database
							Xref priSymbolRef = new Xref(priSymbol.getTextContent(), dsSymbol);
							map.get(priIdRef).add(priSymbolRef);

							name2synonym.add(priId.getTextContent());
							name2synonym.add("\t");
							name2synonym.add(priSymbol.getTextContent());
							name2synonym.add("\t");
							
							//Add the secondary symbols if there is any
							NodeList secSymbolList = document.getElementsByTagName(XMLsec2pri.secSymbolNode);
							if (secSymbolList.getLength() == 0) {//Going to the next row if there is no synonym 
								name2synonym.add("\n");
								listOfname2symbol.add(name2synonym);
								name2synonym = new ArrayList<>();
								}
							
							if (secSymbolList.getLength() != 0) {
								if (!XMLsec2pri.secSymbolNodeTag.equalsIgnoreCase("NA")) { //when there is tag for the node
									
//									for (int itr = 0; itr < secSymbolList.getLength(); itr++) {

									Node node = secSymbolList.item(0); // Retrieve the first item
																		
									if (node != null && node.getNodeType() == Node.ELEMENT_NODE) {
										Element eElement = (Element) node;
										NodeList secSymbols = eElement.getElementsByTagName(XMLsec2pri.secSymbolNodeTag);
										for (int itr = 0; itr < secSymbols.getLength(); itr++) {
											Element secSymbol = (Element) secSymbols.item(itr);
											Xref secSymbolRef = new Xref(secSymbol.getTextContent(), dsSymbol, false); //secondary symbols so idPrimary = false
											map.get(priIdRef).add(secSymbolRef);
											
											if(itr == 0) {
												name2synonym.add(secSymbol.getTextContent());
												
												//Add the list to list of list for the secondary to primary id mapping in tsv
												listOfname2symbol.add(name2synonym);
												name2synonym = new ArrayList<>();
												} else {
													name2synonym.add(priId.getTextContent());
													name2synonym.add("\t");
													name2synonym.add(priSymbol.getTextContent());
													name2synonym.add("\t");
													name2synonym.add(secSymbol.getTextContent());
													//Add the list to list of list for the secondary to primary id mapping in tsv
													listOfname2symbol.add(name2synonym);
													name2synonym = new ArrayList<>();
													}
												}
//											}
										}
									} else { //when there is no tag for the node
										Element secSymbol = (Element) secIdList.item(0); // assumption: there is only one name used by the database
										Xref secSymbolRef = new Xref(secSymbol.getTextContent(), dsSymbol);
										map.get(priIdRef).add(secSymbolRef);
										
										name2synonym.add(secSymbol.getTextContent());
										//Add the list to list of list for the secondary to primary id mapping in tsv
										listOfname2symbol.add(name2synonym);
										name2synonym = new ArrayList<>();

									}
								}
//							break;
							}
						
						counter++;
						if (counter == 5000) {
							counter2++;
							System.out.println("5k mark " + counter2 + ": " + entry);
							counter = 0;
							addEntries(map);
							map.clear();
							// finished = true;
							}
						}
					}
				
				File output_pri_Tsv = new File(outputDir, sourceName + "_primaryIDs.tsv");
				FileWriter writer_pri = new FileWriter(output_pri_Tsv); 
				for (int i = 0; i < listOfpri.stream().count(); i++) {
					List<String> list = listOfpri.get(i);
					for (String str:list) {
						writer_pri.write(str);
						}
					writer_pri.write(System.lineSeparator());
				}
				writer_pri.close();
				System.out.println("[INFO]: List of primary IDs is written");
				
				File outputTsv = new File(outputDir, sourceName + "_secIds.tsv");
				FileWriter writer = new FileWriter(outputTsv); 
				for (int i = 0; i < listOfsec2pri.stream().count(); i++) {
					List<String> list = listOfsec2pri.get(i);
					for (String str:list) {
						writer.write(str);
						}
					writer.write(System.lineSeparator());
				}
				writer.close();
				System.out.println("[INFO]: Secondary to primary id table is written");
				
				File output_name_Tsv = new File(outputDir, sourceName + "_name2symbols.tsv");
				FileWriter writer_name = new FileWriter(output_name_Tsv); 
				for (int i = 0; i < listOfname2symbol.stream().count(); i++) {
					List<String> list = listOfname2symbol.get(i);
					for (String str:list) {
						writer_name.write(str);
						}
					writer_name.write(System.lineSeparator());
				}
				writer_name.close();
				System.out.println("[INFO]: Name to symbols table is written");
				
				System.out.println("Start to the creation of the database, might take some time");
				addEntries(map);
				}
		newDb.finalize();
		System.out.println("[INFO]: Database finished.");
		System.out.println(new Date());

		}
		catch (Exception e) {
			e.printStackTrace();
			}
		}
	
	private static void setupDatasources() {
		DataSourceTxt.init();
		dsId = DataSource.getExistingBySystemCode(XMLsec2pri.sourceIdCode);
		dsSymbol = DataSource.getExistingBySystemCode(XMLsec2pri.sourceSymbolCode);
		}
	
	
	private static void createDb(File outputFile) throws IDMapperException {
		
		newDb = new GdbConstructImpl4(outputFile.getAbsolutePath(),new DataDerby(), DBConnector.PROP_RECREATE);
		newDb.createGdbTables();
		newDb.preInsert();
			
		String dateStr = new SimpleDateFormat("yyyyMMdd").format(new Date());
		newDb.setInfo("BUILDDATE", dateStr);
		newDb.setInfo("DATASOURCENAME", TXTsec2pri.sourceName);
		newDb.setInfo("DATASOURCEVERSION", DbVersion);
		newDb.setInfo("BRIDGEDBVERSION", BridgeDbVersion);
		newDb.setInfo("DATATYPE", "Identifiers");	

	}
	
	private static void addEntries(Map<Xref, Set<Xref>> dbEntries) throws IDMapperException {
		Set<Xref> addedXrefs = new HashSet<Xref>();
		for (Xref ref : dbEntries.keySet()) {
			Xref mainXref = ref;
			//System.out.println("mainXref: " + mainXref.isPrimary());

			if (addedXrefs.add(mainXref)) newDb.addGene(mainXref);
			newDb.addLink(mainXref, mainXref);

			for (Xref rightXref : dbEntries.get(mainXref)) {
				if (!rightXref.equals(mainXref) && rightXref != null) {
					if (addedXrefs.add(rightXref)) newDb.addGene(rightXref);
					//System.out.println("rightXref: " + rightXref.isPrimary());

					newDb.addLink(mainXref, rightXref);
				}
			}
			// System.out.println("[INFO]: Commit " + mainXref);
			newDb.commit();
		}
	}
	
	}  