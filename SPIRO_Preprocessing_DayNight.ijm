/*
 * MODIFIED SPIRO PREPROCESSING MACRO
 * Sorts images into Day/Night folders with ORIGINAL drift correction
 */

// GLOBAL VARIABLES
var maindir;
var listInmaindir;
var resultsdir;
var ppdir;
var daydir;
var nightdir;

var DEBUG = false;
var freshstart = false;

var runRegistration;
var batchsize = 350;

// CROP COORDINATES
var cropX;
var cropY;
var cropWidth;
var cropHeight;
var cropDefined = false;

macro "SPIRO_Preprocessing_DayNight" {
	
	List.setCommands;
	if(List.get("TurboReg ")!="") {
		turboreginstalled = true;
	} else {
		turboreginstalled = false;
	}
	if(List.get("MultiStackReg")!="") {
		multistackreginstalled = true;
	} else {
		multistackreginstalled = false;
	} 
	if (!turboreginstalled || !multistackreginstalled) { 
		Dialog.create("Plugin not found"); 
		Dialog.addMessage("Plugins TurboReg and/or MultiStackReg not found. Please refer to the SPIRO manual for installation instructions.");
		Dialog.addCheckbox("I understand.", false);
		Dialog.show();
		usercheck = Dialog.getCheckbox();
		if (usercheck == true)
			exit;
	}

	print("=================================================\n"+ 
		  "SPIRO Preprocessing with Day/Night Sorting\n" +
		  "=================================================");
	selectWindow("Log");

	showMessage("Welcome to the SPIRO preprocessing macro (Day/Night version)!\n" +
		"Images will be sorted into Day/ and Night/ folders.\n" +
		"---------\n" +
		"Alternative types of run (hold down then press OK):\n" +
		"SHIFT = Fresh Start mode, all data from any previous run will be deleted\n" +
		"CTRL = Debug mode\n");

	wait(1000);

	if (isKeyDown("control"))
		DEBUG = getBoolean("CTRL key pressed. Run macro in debug mode?");

	if (isKeyDown("shift"))
		freshstart = getBoolean("SHIFT key pressed. Run macro in Fresh Start mode? This will delete all data from the previous run.");

	maindir = getDirectory("Choose a Directory");
	listInmaindir = getFileList(maindir);
	resultsdir = maindir + "Results" + File.separator;
	if (!File.isDirectory(resultsdir))
		File.makeDirectory(resultsdir);
	
	ppdir = resultsdir + "Preprocessing" + File.separator;
	if (!File.isDirectory(ppdir))
		File.makeDirectory(ppdir);
	
	// Create Day and Night subdirectories
	daydir = ppdir + "Day" + File.separator;
	nightdir = ppdir + "Night" + File.separator;
	if (!File.isDirectory(daydir))
		File.makeDirectory(daydir);
	if (!File.isDirectory(nightdir))
		File.makeDirectory(nightdir);
	
	// Filter out non-plate files
	for (fileindex = 0; fileindex < listInmaindir.length; fileindex++) {
		if (indexOf(listInmaindir[fileindex], "plate") == -1)
			listInmaindir = Array.deleteValue(listInmaindir, listInmaindir[fileindex]); 
	}
	
	// Get user choice on drift correction
	Dialog.create("Drift Correction");
	Dialog.addMessage("Would you like to carry out drift correction (registration)?\n" +
	    "Please note that this step may take up a lot of time and RAM for large datasets.");
	dialogchoices = newArray("Yes", "No");
	Dialog.addChoice("", dialogchoices);
	Dialog.show();
	regUserInput = Dialog.getChoice();
	
	if (regUserInput == "Yes") {
		runRegistration = true;
	} else {
		runRegistration = false;
	}
	
	// Main processing
	if (freshstart)
		deleteOutputPP();
	
	scale();
	cropnGreenChSorted();
	
	if (runRegistration) {
		registerSorted();
	} else {
		print("Step 3/3 Drift correction skipped due to user choice");
	}
	
	deleteOutputPP();
	
	list = getList("window.titles");
	list = Array.deleteValue(list, "Log");
	for (i=0; i<list.length; i++) {
		winame = list[i];
		selectWindow(winame);
		run("Close");
	}
	
	print("\nPreprocessing is complete.");
	print("Images have been sorted into Day/ and Night/ folders in the Preprocessing directory.");
	selectWindow("Log");

	// ============================================================
	// FUNCTIONS
	// ============================================================

	function scale() {
		if (is("Batch Mode"))
			setBatchMode(false);
		print("Step 1/3 Setting scale and defining crop area...");
		
		plate1dir = maindir + listInmaindir[0];
		listInplate1dir = getFileList(plate1dir);
		Array.sort(listInplate1dir);
		
		// Find first image file
		imgfile = "";
		for (i = 0; i < listInplate1dir.length; i++) {
			if (endsWith(toLowerCase(listInplate1dir[i]), ".png") || 
			    endsWith(toLowerCase(listInplate1dir[i]), ".tif") ||
			    endsWith(toLowerCase(listInplate1dir[i]), ".jpg")) {
				imgfile = listInplate1dir[i];
				break;
			}
		}
		
		open(plate1dir + imgfile);
		run("Set Scale...", "distance=1 known=1 unit=pixel");
		run("Set Measurements...", "area bounding display redirect=None decimal=3");
		run("Original Scale");
		
		// USER STEP 1: SET THE SCALE BAR
		setTool("line");
		userconfirm = false;
		while (!userconfirm) {
			Dialog.createNonBlocking("Scale Bar Setup");
			Dialog.addMessage("STEP 1: Draw a line corresponding to 1 cm on the scale bar.\n" +
				"Hold SHIFT while drawing to keep the line horizontal.\n" +
				"The scale bar is typically at the bottom-right of the image.");
			Dialog.addCheckbox("I have drawn the 1 cm scale bar line", false);
			Dialog.show();
			userconfirm = Dialog.getCheckbox();
		}
		
		run("Set Measurements...", "area bounding display redirect=None decimal=3");
		run("Measure");
		Table.rename("Results", "scalebar");
		length = getResult('Length', nResults - 1);
		run("Set Scale...", "distance=" + length + " known=1 unit=cm global");
		
		print("Scale set: 1 cm = " + length + " pixels");
		
		// USER STEP 2: DEFINE THE CROP AREA
		userconfirm = false;
		roiManager("reset");
		setTool("rectangle");
		
		while (!userconfirm) {
			Dialog.createNonBlocking("Define Crop Area");
			Dialog.addMessage("STEP 2: Use the Rectangle tool to select the area you want to crop.\n" +
				"Draw a rectangle around the region of interest.\n" +
				"The crop will be applied to ALL images in your dataset.");
			Dialog.addCheckbox("I have defined the crop area", false);
			Dialog.show();
			userconfirm = Dialog.getCheckbox();
		}
		
		if (selectionType() == 0) {
			getBoundingRect(cropX, cropY, cropWidth, cropHeight);
			cropDefined = true;
			print("Crop area defined: X=" + cropX + ", Y=" + cropY + ", Width=" + cropWidth + ", Height=" + cropHeight);
		} else {
			Dialog.create("Error");
			Dialog.addMessage("No crop area detected. Please draw a rectangle.");
			Dialog.show();
			exit;
		}
		
		Table.create("cropcoordinates");
		Table.set("xcrop", 0, cropX, "cropcoordinates");
		Table.set("ycrop", 0, cropY, "cropcoordinates");
		Table.set("wcrop", 0, cropWidth, "cropcoordinates");
		Table.set("hcrop", 0, cropHeight, "cropcoordinates");
		
		close();
		selectWindow("scalebar");
		run("Close");
		
		print("Crop coordinates saved. These will be applied to all images.");
	}
	
	function cropnGreenChSorted() {
		if (!is("Batch Mode"))
			setBatchMode(true);
		print("\nStep 2/3 Processing and sorting images into Day/Night folders...\n" +
			  "It may look like nothing is happening, please be patient.");
		
		for (plateno = 0; plateno < listInmaindir.length; plateno++) {
			platefolder = listInmaindir[plateno];
			platedir = maindir + platefolder;
			platename = File.getName(platedir);
			listInplatedir = getFileList(platedir);
			Array.sort(listInplatedir);
			
			print("Processing " + platename);
			
			for (fileno = 0; fileno < listInplatedir.length; fileno++) {
				filename = listInplatedir[fileno];
				
				// Skip non-image files
				if (!endsWith(toLowerCase(filename), ".png") && 
				    !endsWith(toLowerCase(filename), ".tif") &&
				    !endsWith(toLowerCase(filename), ".jpg")) {
					continue;
				}
				
				// Check if filename contains day or night
				filename_lower = toLowerCase(filename);
				isDay = indexOf(filename_lower, "day") >= 0;
				isNight = indexOf(filename_lower, "night") >= 0;
				
				// Skip if neither day nor night
				if (!isDay && !isNight) {
					print("  Skipping: " + filename + " (no day/night label)");
					continue;
				}
				
				// Open image
				open(platedir + filename);
				img = getTitle();
				
				// Get crop coordinates
				xcrop = Table.get("xcrop", 0, "cropcoordinates");
				ycrop = Table.get("ycrop", 0, "cropcoordinates");
				wcrop = Table.get("wcrop", 0, "cropcoordinates");
				hcrop = Table.get("hcrop", 0, "cropcoordinates");
				
				// Crop
				makeRectangle(xcrop, ycrop, wcrop, hcrop);
				run("Crop");
				
				// If it's a stack, process each slice separately
				stacksize = nSlices();
				
				if (stacksize > 1) {
					// For stacks: split channels, keep green, save as stack
					run("Split Channels");
					imglist = getList("image.titles");
					for (i = 0; i < imglist.length; i++) {
						imgname = imglist[i];
						if (indexOf(imgname, "green") > 0) {
							selectWindow(imgname);
							rename(img);
						} else if (indexOf(imgname, "red") > 0 || indexOf(imgname, "blue") > 0) {
							selectWindow(imgname);
							close();
						}
					}
					
					// Get the green channel image
					selectWindow(img);
					
					// Determine output directory and save
					filenameNoExt = File.nameWithoutExtension;
					if (isDay) {
						saveAs("Tiff", daydir + filenameNoExt + "_GreenCh.tif");
						print("  Saved (Day): " + filenameNoExt + "_GreenCh.tif");
					} else if (isNight) {
						saveAs("Tiff", nightdir + filenameNoExt + "_GreenCh.tif");
						print("  Saved (Night): " + filenameNoExt + "_GreenCh.tif");
					}
					close();
					
				} else {
					// For single images: split channels, keep green
					run("Split Channels");
					imglist = getList("image.titles");
					for (i = 0; i < imglist.length; i++) {
						imgname = imglist[i];
						if (indexOf(imgname, "green") > 0) {
							selectWindow(imgname);
							rename(img);
						} else if (indexOf(imgname, "red") > 0 || indexOf(imgname, "blue") > 0) {
							selectWindow(imgname);
							close();
						}
					}
					
					// Determine output directory and save
					selectWindow(img);
					filenameNoExt = File.nameWithoutExtension;
					if (isDay) {
						saveAs("Tiff", daydir + filenameNoExt + "_GreenCh.tif");
						print("  Saved (Day): " + filenameNoExt + "_GreenCh.tif");
					} else if (isNight) {
						saveAs("Tiff", nightdir + filenameNoExt + "_GreenCh.tif");
						print("  Saved (Night): " + filenameNoExt + "_GreenCh.tif");
					}
					close();
				}
			}
		}
		
		selectWindow("cropcoordinates");
		run("Close");
	}
	
	function registerSorted() {
		if (!is("Batch Mode"))
			setBatchMode(true);
		print("\nStep 3/3 Correcting drift in Day and Night folders...\n" +
			  "It may look like nothing is happening, please be patient.");
		
		// Register Day folder - USING ORIGINAL LOGIC
		print("Registering Day images...");
		listInday = getFileList(daydir);
		Array.sort(listInday);
		
		for (fileno = 0; fileno < listInday.length; fileno++) {
			grplatename = listInday[fileno];
			if (indexOf(grplatename, "GreenCh") > -1) {
				pfsplit = split(grplatename, "_");
				platename = pfsplit[0];
				print("  Processing: " + platename);
				
				open(daydir + grplatename);
				
				run("Subtract Background...", "rolling=30 stack");
				tfn = daydir + "Transformation";
				run("MultiStackReg", "stack_1=" + grplatename + " action_1=Align file_1=" + tfn +
					" stack_2=None action_2=Ignore file_2=[] transformation=Translation save");
				close(grplatename);
				
				open(daydir + grplatename);
				run("MultiStackReg", "stack_1=" + grplatename + " action_1=[Load Transformation File] file_1=" + tfn +
					" stack_2=None action_2=Ignore file_2=[] transformation=[Translation]");
				
				saveAs("Tiff", daydir + platename + "_preprocessed.tif");
				close();
				filedelete = File.delete(daydir + grplatename);
			}
		}
		
		// Register Night folder - USING ORIGINAL LOGIC
		print("Registering Night images...");
		listInnight = getFileList(nightdir);
		Array.sort(listInnight);
		
		for (fileno = 0; fileno < listInnight.length; fileno++) {
			grplatename = listInnight[fileno];
			if (indexOf(grplatename, "GreenCh") > -1) {
				pfsplit = split(grplatename, "_");
				platename = pfsplit[0];
				print("  Processing: " + platename);
				
				open(nightdir + grplatename);
				
				run("Subtract Background...", "rolling=30 stack");
				tfn = nightdir + "Transformation";
				run("MultiStackReg", "stack_1=" + grplatename + " action_1=Align file_1=" + tfn +
					" stack_2=None action_2=Ignore file_2=[] transformation=Translation save");
				close(grplatename);
				
				open(nightdir + grplatename);
				run("MultiStackReg", "stack_1=" + grplatename + " action_1=[Load Transformation File] file_1=" + tfn +
					" stack_2=None action_2=Ignore file_2=[] transformation=[Translation]");
				
				saveAs("Tiff", nightdir + platename + "_preprocessed.tif");
				close();
				filedelete = File.delete(nightdir + grplatename);
			}
		}
		
		print("Drift correction complete for both Day and Night folders.");
	}
	
	function deleteOutputPP() {
		print("Cleaning up intermediate files...");
		
		if (freshstart) {
			print("Fresh start: deleting output from any previous run");
			listInday = getFileList(daydir);
			for (i = 0; i < listInday.length; i++) {
				File.delete(daydir + listInday[i]);
			}
			listInnight = getFileList(nightdir);
			for (i = 0; i < listInnight.length; i++) {
				File.delete(nightdir + listInnight[i]);
			}
		}
	}
}
