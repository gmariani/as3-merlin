import cv.managers.UpdateManager;
import cv.merlin.AboutWindow;
import cv.merlin.PseudoThread;
import cv.merlin.UpdateWindow;
import cv.merlin.formats.*;

import com.google.analytics.GATracker; //this is the actual tracking class
import com.google.analytics.AnalyticsTracker; //this is an interface that the GATracker class implements

import flash.errors.IOError;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.events.MouseEvent;
import flash.filesystem.File;
import flash.utils.setTimeout;
import flash.desktop.NativeApplication;

import mx.collections.*;
import mx.events.FlexEvent;
import mx.utils.StringUtil;
import mx.managers.SystemManager;

private var tracker:AnalyticsTracker;
private var fileDir:File = File.desktopDirectory;
private var fileCurrentDir:File;
private var arrFileList:Array = new Array();
private var isCancelled:Boolean = false;
private var isRename:Boolean = true;
private var isMove:Boolean = true;
private var isDelete:Boolean = true;
private var isFamily:Boolean = true;
private var nRenameCount:int = 0;
private var nMoveCount:int = 0;
private var nDeleteCount:int = 0;
private var nCounter:int = 0;
private var aboutWin:AboutWindow;
private var updateWin:UpdateWindow;
private var app:NativeApplication = NativeApplication.nativeApplication;
private var um:UpdateManager;

private var thread:PseudoThread;
private var errorMessage:String;
private var skipToEnd:Boolean = false;
private var arrFontList:Array;

private function init(event:FlexEvent):void {
	fileDir.addEventListener(Event.SELECT, onDirSelection);
	
    // Init Updater
	um = UpdateManager.instance;
	um.addEventListener(UpdateManager.AVAILABLE, updateHandler, false, 0, true);
	um.updateURL = "http://www.coursevector.com/projects/merlin/update.xml";
	um.checkNow();
}

private function initTracker():void {
	// Analytics
	tracker = new GATracker(this, "UA-349755-7", "AS3", false);
	tracker.trackPageview("/merlin/MainScreen");
}

private function updateHandler(event:Event = null):void {
	updateWin = new UpdateWindow();
	updateWin.open();
}

private function onClickOpen():void {
	fileDir.browseForDirectory("Select Folder");
}

private function onClickAbout():void {
	aboutWin = new AboutWindow();
	aboutWin.open();
}

private function onError(event:IOErrorEvent):void {
	trace("IO Error - " + event.text);
	tracker.trackEvent(".merlin", "errorIO", "", -1);
}

private function onDirSelection(e:Event):void {
	fileCurrentDir = e.target as File;
	fileCurrentDir.addEventListener(IOErrorEvent.IO_ERROR, onError, false, 0, true);
	arrFileList = fileCurrentDir.getDirectoryListing();
	txtInfo.htmlText = fileCurrentDir.nativePath;
    btnStart.enabled = true;
    nRenameCount = 0;
    nMoveCount = 0;
    nDeleteCount = 0;
    nCounter = 0;
    skipToEnd = false;
    errorMessage = null;
    arrFontList = new Array();
}

private function cbHandler(event:MouseEvent):void {
	isRename = cbRename.selected;
	isMove = cbMove.selected;
	isDelete = cbDelete.selected;
	isFamily = cbFamily.selected;
}

private function startHandler(event:MouseEvent):void {
	tracker.trackEvent(".merlin", "start", "", -1);
	
	isCancelled = false;
	btnStart.enabled = false;
	pbProgress.indeterminate = true;
	pbProgress.label = "Working...";
	pbProgress.visible = true;
	cbRename.enabled = false;
	cbMove.enabled = false;
	cbDelete.enabled = false;
	cbFamily.enabled = false;
	
	txtInfo.htmlText = fileCurrentDir.nativePath + "<br><br>Searching directories...";
	
	setTimeout(searchDirectory, 500, arrFileList, fileCurrentDir);
}

private function searchDirectory(arr:Array, fileSubDir:File, isChild:Boolean = false):void {
	var l:uint = arr.length;
	
	for(var i:uint = 0; i < l; i++) {
		if(arr[i].isDirectory) {
			searchDirectory(arr[i].getDirectoryListing(), arr[i], true);
		} else {
			arrFontList.push({file:arr[i], dir:fileSubDir});
		}
    }
    
    // Only do once
    if(!isChild) {
    	
    	pbProgress.indeterminate = false;
    	pbProgress.minimum = 0;
    	pbProgress.maximum = arrFontList.length;
    	
		thread = new PseudoThread(this.systemManager, organize, { curIndex: 0, fonts: arrFontList });
		thread.addEventListener("threadComplete", threadCompleteHandler, false, 0, true);
    }
}

private function threadCompleteHandler(event:Event):void {
	PseudoThread(event.currentTarget).removeEventListener("threadComplete", threadCompleteHandler);
	thread = null;
	pbProgress.visible = false;
	skipToEnd = false;
	cbRename.enabled = true;
	cbMove.enabled = true;
	cbDelete.enabled = true;
	cbFamily.enabled = true;
	txtInfo.htmlText = fileCurrentDir.nativePath + "<br><br>";
	if(errorMessage != null) txtInfo.htmlText += "<b>" + errorMessage + "</b><br><br>";
	txtInfo.htmlText += "Renamed: " + nRenameCount + " | Moved: " + nMoveCount + " | Deleted: " + nDeleteCount;
}

private function renameRelated(f:File, strExt:String, oldExtension:String, strFontName:String, fileSubDir:File):File {
	if(oldExtension == "pfb" && f.exists) {
		var fDest:File = fileSubDir.resolvePath(strFontName + strExt);
    	f.moveTo(fDest, true);
    	f = fDest;
    	nRenameCount++;
    	return f;
    }
    return null;
}

private function moveRelated(f:File, strExt:String, oldExtension:String, strFontName:String, fileSubDir:File, fileDirChar:File):void {
    if(f == null) return;
    
    var fDest:File = fileDirChar.resolvePath(strFontName + strExt);
	if(oldExtension == "pfb") {
		if(fDest.url.toLowerCase() != f.url.toLowerCase()) {
			if(fDest.exists) {
				// Check if duplicate exists
				if(isDelete) {
					try {
						trace("Delete File - " + f.url);
					    f.deleteFileAsync();
					    nDeleteCount++;
					} catch (e:Error) {
						trace(e.getStackTrace());
						tracker.trackEvent(".merlin", "errorDelete", "", -1);
					    errorMessage = "Delete related file - " + e.message + " : " + f.nativePath;
					    skipToEnd = true;
					}
				} else {
					fDest = fileSubDir.resolvePath(strFontName + "_" + nCounter + strExt);
					f.moveTo(fDest, false);
				}
			} else {
				// Move to folder
				try {
					trace("Move - " + f.url + " > " + fDest.url);
				    f.moveTo(fDest, false);
				    nMoveCount++;
				} catch (e:Error) {
					trace(e.getStackTrace());
					tracker.trackEvent(".merlin", "errorMove", "", -1);
					errorMessage = "Move related file - " + e.message + " : " + f.nativePath + " > " + fDest.nativePath;
					skipToEnd = true;
				}
			}
		}
	}
}

private function organize(obj:Object):Boolean {
	if(obj.curIndex >= obj.fonts.length) return false;
	
	var sourceFile:File = obj.fonts[obj.curIndex].file;
	var fileSubDir:File = obj.fonts[obj.curIndex].dir;
	var destination:File;
	var pfmFile:File;
	skipToEnd = false;
	
	// Only organize PFB, AFM, INF, PFM, TTF and OTF files
	if(sourceFile.extension == null) skipToEnd = true; //return;
	
	if(!skipToEnd) {
		var oldExtension:String = sourceFile.extension.toLowerCase();
		var oldFileName:String = sourceFile.name.substr(0, oldExtension.length * -1);
		var newExtension:String;
		
		if(oldExtension == "ttf" || oldExtension == "otf" || oldExtension == "pfb" || oldExtension == "afm" || oldExtension == "inf") {
			if(sourceFile.exists) {
				var strFontName:String = "";
				var strFontFamily:String = "";
				try {
					if(TTF.isValid(sourceFile)) {
						//trace("TTF");
						var ttf:TTF = new TTF(sourceFile);
						strFontName = ttf.fontName;
						strFontFamily = ttf.fontFamily;
						newExtension = "ttf";
					} else if(OTF.isValid(sourceFile)) {
						//trace("OTF");
						var otf:OTF = new OTF(sourceFile);
						strFontName = otf.fontName;
						newExtension = "otf";
					} else if(AFM.isValid(sourceFile)) {
						//trace("AFM");
						var afm:AFM = new AFM(sourceFile);
						strFontName = afm.fontName;
						newExtension = "afm";
					}  else if(INF.isValid(sourceFile)) {
						//trace("INF");
						var inf:INF = new INF(sourceFile);
						strFontName = inf.fontName;
						newExtension = "inf";
					} else if(Type1.isValid(sourceFile)) {
						//trace("Type1");
						var typ1:Type1 = new Type1(sourceFile);
						strFontName = typ1.fontName;
						newExtension = "pfb";
						pfmFile = sourceFile.parent.resolvePath(oldFileName + "pfm");
					}
				} catch(e:Error) {
					trace(e.getStackTrace());
					tracker.trackEvent(".merlin", "errorParse", "", -1);
					errorMessage = "Parse font - " + e.message + " : " + sourceFile.nativePath;
					skipToEnd = true;
				}
				
				if(strFontName == "" || skipToEnd) {
					skipToEnd = true;//return;
				} else {
					// Remove Illegal Characters
					
					// Replace : with -
					var regex:RegExp = /\Q:\E/
					strFontName = strFontName.replace(regex, "-");
					
					// Remove special characters
					regex = /[^\w\s\.\d1@#$%&()`~\[\]\{\},\=\+]/gi
					strFontName = strFontName.replace(regex, "");
					
					strFontName = StringUtil.trim(strFontName);		
					var strChar:String = strFontName.substr(0, 1);
					var strFamily:String = strFontFamily;
					var strNewname:String = strFontName + "." + newExtension;
					var fileOldDir:File = sourceFile.parent;
				}
			} else {
				skipToEnd = true;
				//return;
			}
		} else {
			skipToEnd = true;
			//return;
		}
	}
	
	if(!skipToEnd) {
		if(isRename) {
			// Rename
			destination = fileSubDir.resolvePath(strNewname);
			
			if(destination.url.toLowerCase() != sourceFile.url.toLowerCase()) {
				try {
					trace("Rename - " + sourceFile.nativePath + " > " + destination.nativePath);
				    sourceFile.moveTo(destination, true);
				    sourceFile = destination;
				    nRenameCount++;
				    
				    pfmFile = renameRelated(pfmFile, ".pfm", oldExtension, strFontName, fileSubDir);
				} catch (e:Error) {
					trace(e.getStackTrace());
					tracker.trackEvent(".merlin", "errorRename", "", -1);
				    errorMessage = "Rename file - " + e.message + " : " + sourceFile.nativePath + " > " + destination.nativePath;
					skipToEnd = true;
				}
			} else {
				destination = sourceFile;
			}
		}
	}
		
	if(!skipToEnd) {
		if(isMove) {
			// Create directory
			var fileDirChar:File = fileCurrentDir;
			fileDirChar = fileDirChar.resolvePath(fileCurrentDir.url + "/" + strChar.toLowerCase() + "/");
			if(isFamily && strFamily != "") fileDirChar = fileDirChar.resolvePath(strFamily + "/");
			fileDirChar.createDirectory();
			
			destination = fileDirChar.resolvePath(strNewname);
			
			// See if file is already at correct location
			if(destination.url.toLowerCase() != sourceFile.url.toLowerCase()) {
				if(destination.exists) {
					// Check if duplicate exists
					if(isDelete) {
						try {
							trace("Delete File - " + sourceFile.url);
						    //sourceFile.deleteFileAsync();
							sourceFile.deleteFile();
						    nDeleteCount++;
						} catch (e:Error) {
							trace(e.getStackTrace());
							tracker.trackEvent(".merlin", "errorDeleteDuplicate", "", -1);
						    errorMessage = "Delete duplicate file - " + e.message + " : " + sourceFile.nativePath;
							skipToEnd = true;
						}
					} else {
						nCounter++;
						destination = fileSubDir.resolvePath(strFontName + "_" + nCounter + "." + newExtension);
						sourceFile.moveTo(destination, false);
					}
				} else {
					// Move to folder
					try {
						trace("Move - " + sourceFile.url + " > " + destination.url);
					    sourceFile.moveTo(destination, false);
					    nMoveCount++;
					} catch (e:Error) {
						trace(e.getStackTrace());
						tracker.trackEvent(".merlin", "errorMoveToFolder", "", -1);
					    errorMessage = "Move to folder - " + e.message + " : " + sourceFile.nativePath + " > " + destination.nativePath;
						skipToEnd = true;
					}
				}
			} else {
				// Skip
			}
			
			if(!skipToEnd) {
				moveRelated(pfmFile, ".pfm", oldExtension, strFontName, fileSubDir, fileDirChar);
				
				// Delete old Folder if Empty
				try {
					trace("Delete Dir - " + fileOldDir.url);
					fileOldDir.deleteDirectory();
				} catch (error:IOError) {
					tracker.trackEvent(".merlin", "errorDeleteDir", "", -1);
					trace("Delete Dir - " + error.message);
				}
			}
		}
	}
	
	// Update Stats
	if(errorMessage == null) {
		pbProgress.label = "Font " + obj.curIndex + " of " + obj.fonts.length;
		pbProgress.setProgress(obj.curIndex, obj.fonts.length);
		txtInfo.htmlText = fileCurrentDir.nativePath + "<br><br>" + (destination ? destination.name : sourceFile.name) + "<br>Renamed: " + nRenameCount + " | Moved: " + nMoveCount + " | Deleted: " + nDeleteCount;
	}
	
	obj.curIndex++;
	return (errorMessage != null) ? false : (obj.curIndex < obj.fonts.length);
}