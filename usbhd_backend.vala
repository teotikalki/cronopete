/*
 Copyright 2011 (C) Raster Software Vigo (Sergio Costas)

 This file is part of Cronopete

 Nanockup is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 3 of the License, or
 (at your option) any later version.

 Nanockup is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>. */

using GLib;
using Posix;
using Gee;


class usbhd_backend: Object, backends {

	private string backup_path;
	private string id;
	private string? cbackup_path;
	private string? cfinal_path;
	private string? last_backup;
	private string drive_path;
	private VolumeMonitor monitor;
	public bool _available;
	public bool available {
		get {
			return (this._available);
		}
	}
	private int last_msg;

	private string get_backup_path(time_t backup) {
		
		var ctime = GLib.Time.local(backup);
		var basepath="%04d_%02d_%02d_%02d:%02d:%02d_%ld".printf(1900+ctime.year,ctime.month+1,ctime.day,ctime.hour,ctime.minute,ctime.second,backup);
		return basepath;
		
	}
	
	public BACKUP_RETVAL restore_file(string filename,time_t backup, string output_filename) {
	
		var origin_path = Path.build_filename(this.backup_path,this.get_backup_path(backup),filename);

		File origin;
		
		origin=File.new_for_path(origin_path);
		origin.copy_async.begin(File.new_for_path(output_filename),FileCopyFlags.OVERWRITE,GLib.Priority.DEFAULT,null,null, (obj,res) => {
			try {
				origin.copy_async.end(res);
				this.restore_ended(this,output_filename,BACKUP_RETVAL.OK);
			} catch (IOError e2) {
				GLib.stdout.printf("Error2 %s\n",e2.message);
				if (e2 is IOError.NO_SPACE) {
					Posix.unlink(output_filename);
					this.restore_ended(this,output_filename,BACKUP_RETVAL.NO_SPC);
				} else {
					this.restore_ended(this,output_filename,BACKUP_RETVAL.CANT_COPY);
				}
			}
		});
		
		return BACKUP_RETVAL.IN_PROCCESS;
	}
	
	public usbhd_backend(string bpath) {
	
		var tmpid=bpath.split("/");
		foreach (string v in tmpid) {
			this.id=v;
		}
		this.backup_path=Path.build_filename(bpath,"cronopete",Environment.get_user_name());
		this.cbackup_path=null;
		this.cfinal_path=null;
		this.drive_path=bpath;
		
		this.monitor = VolumeMonitor.get();
		this.monitor.mount_added.connect_after(this.refresh_connect);
		this.monitor.mount_removed.connect_after(this.refresh_connect);
		this.last_msg=0;
		this.refresh_connect();
		
	}


	public bool get_filelist(string current_path, time_t backup, out Gee.List<FilelistIcons.file_info ?> files, out string date) {
	
		FileInfo info_file;
		FileType typeinfo;

		try {
		
			files = new Gee.ArrayList<FilelistIcons.file_info ?>();
		
			var basepath=this.get_backup_path(backup);

			date=basepath.dup();
	
			var finalpath = Path.build_filename(this.backup_path,basepath,current_path);
	
			var directory = File.new_for_path(finalpath);
			var listfile = directory.enumerate_children(FILE_ATTRIBUTE_TIME_MODIFIED+","+FILE_ATTRIBUTE_STANDARD_NAME+","+FILE_ATTRIBUTE_STANDARD_TYPE+","+FILE_ATTRIBUTE_STANDARD_SIZE,FileQueryInfoFlags.NOFOLLOW_SYMLINKS,null);
		
			while ((info_file = listfile.next_file(null)) != null) {

				var tmpinfo = FilelistIcons.file_info();

				typeinfo=info_file.get_file_type();
				tmpinfo.name=info_file.get_name().dup();

				if (typeinfo==FileType.DIRECTORY) {
					tmpinfo.isdir=true;
				} else {
					tmpinfo.isdir=false;
				}
				
				info_file.get_modification_time(out tmpinfo.mod_time);
				tmpinfo.size = info_file.get_size();
				
				files.add(tmpinfo);
				
			}
			return true;
		} catch {
			return false;
		}
	}


	public void refresh_connect() {
	
		var volumes = this.monitor.get_volumes();
		Mount mnt;
		foreach (Volume v in volumes) {		

			mnt=v.get_mount();
			if ((mnt is Mount)==false) {
				continue;
			}

			if (this.drive_path==mnt.get_root().get_path()) {
				this._available=true;
				if (this.last_msg!=1) {
					this.last_msg=1;
					this.status(this);
				}
				return;
			}
		}
		this._available=false;
		if (this.last_msg!=2) {
			this.last_msg=2;
			this.status(this);
		}
	}

	public bool get_free_space(out uint64 total_space, out uint64 free_space) {
	
		if (this._available==false) {
			total_space=0;
			free_space=0;
			return false;
		}
	
		try {
			var file = File.new_for_path(this.drive_path);
			var info = file.query_filesystem_info(FILE_ATTRIBUTE_FILESYSTEM_SIZE+","+FILE_ATTRIBUTE_FILESYSTEM_FREE,null);
			free_space = info.get_attribute_uint64(FILE_ATTRIBUTE_FILESYSTEM_FREE);
			total_space = info.get_attribute_uint64(FILE_ATTRIBUTE_FILESYSTEM_SIZE);
			return true;
		} catch (Error e) {
		}
		total_space = 0;
		free_space = 0;
		return false;
	}

	public string? get_backup_id() {
	
		if (this.id=="") {
			return null;
		} else {
			return (this.id);
		}
	}

	public Gee.List<time_t?>? get_backup_list() {
	
		var blist = new Gee.ArrayList<time_t?>();
		string dirname;
		
		var directory = File.new_for_path(this.backup_path);

		try {
			var myenum = directory.enumerate_children(FILE_ATTRIBUTE_STANDARD_NAME, 0, null);
			
			FileInfo file_info;
		
			// Try to find the last directory, based in the origin's date of creation
		
			while ((file_info = myenum.next_file (null)) != null) {
				
				// If the directory starts with 'B', it's a temporary directory from an
		 		// unfinished backup, so remove it
				
				dirname=file_info.get_name();
				if (dirname[0]!='B') {
					blist.add(long.parse(dirname.substring(20)));
				}
			}
		} catch (Error e) {
	
			// The main directory doesn't exist, so we create it
			try {
				directory.make_directory_with_parents(null);
			} catch (Error e) {
				return null; // Error: can't create the base directory
			}
		}
		return blist;

	}
	
	public bool delete_backup(time_t backup_date) {
	
		var tmppath=this.get_backup_path(backup_date);
		var final_path=Path.build_filename(this.backup_path,tmppath);
		
		Process.spawn_command_line_sync("rm -rf "+final_path);
		return true;
	}


	public BACKUP_RETVAL end_backup() {
	
		if (this.cfinal_path==null) {
			return BACKUP_RETVAL.NO_STARTED;
		}
	
		// sync the disk to ensure that all the data has been commited
		Posix.sync();
		
		// rename the directory from Bxxxxx to xxxxx to confirm the backup
		var directory2 = File.new_for_path(this.cbackup_path);
		try {
			directory2.set_display_name(this.cfinal_path,null);
		} catch (Error e) {
			this.cfinal_path=null;
			return BACKUP_RETVAL.ERROR;
		}
	
		// and sync again the disk to confirm the new name
		Posix.sync();
		this.cfinal_path=null;
		return BACKUP_RETVAL.OK;
	}

	public BACKUP_RETVAL start_backup(out int64 last_backup_time) {
	
		if (this.cfinal_path!=null) {
			return BACKUP_RETVAL.ALREADY_STARTED;
		}
	
		string dirname;
		var directory = File.new_for_path(this.backup_path);
		if (directory.query_exists(null)==false) {
			return BACKUP_RETVAL.NOT_AVAILABLE;
		}
		
		var tmppath=this.get_backup_path(time_t());
		this.cbackup_path=Path.build_filename(this.backup_path,"B"+tmppath);
		this.cfinal_path=tmppath;
		
		string tmp_directory="";
		string tmp_date="";
		string last_date="";

		try {
			var myenum = directory.enumerate_children(FILE_ATTRIBUTE_STANDARD_NAME, 0, null);
			FileInfo file_info;
		
			while ((file_info = myenum.next_file (null)) != null) {
				
				// If the directory starts with 'B', it's a temporary directory from an
		 		// unfinished backup, so remove it
				
				dirname=file_info.get_name();
				if (dirname[0]=='B') {
					Process.spawn_command_line_sync("rm -rf "+Path.build_filename(this.backup_path,dirname));
				} else {
					tmp_date=dirname.substring(20);
					if (tmp_directory=="") {
				
						/* If this is the first path we read, just store it as-is. */
				
						tmp_directory=dirname;
						last_date=tmp_date;
						last_backup_time = int64.parse(tmp_date);
					} else {
				
						/* If not, compare it with the current one, and, if is newer, replace it.
				 		* We use the time from the epoch to avoid problems when a backup is done
				 		* just during the winter or summer time change */

						if (last_date.collate(tmp_date)<0) {
							tmp_directory=dirname;
							last_date=tmp_date;
							last_backup_time = int64.parse(tmp_date);
						}
					}
				}
			}
		} catch (Error e) {
			// The main directory doesn't exist, so we create it
			try {
				this.last_backup=null;
				last_backup_time=0;
				directory.make_directory_with_parents(null);
			} catch (Error e) {
				return BACKUP_RETVAL.CANT_CREATE_BASE; // Error: can't create the base directory
			}
		}

		this.last_backup=Path.build_filename(this.backup_path,tmp_directory);
		
		var directory2 = File.new_for_path(this.cbackup_path);
		try {
			directory2.make_directory_with_parents(null);
		} catch (Error e) {
			return BACKUP_RETVAL.NOT_WRITABLE; // can't create the folder for the current backup
		}
		
		return BACKUP_RETVAL.OK;
	}

	public BACKUP_RETVAL copy_file(string path, time_t mod_time) {
	
		var newfile = Path.build_filename(this.cbackup_path,path);
		File origin;
		
		try {
			origin=File.new_for_path(Path.build_filename(path));
			origin.copy(File.new_for_path(newfile),FileCopyFlags.OVERWRITE,null,null);
		} catch (IOError e) {
			if (e is IOError.NO_SPACE) {
				Posix.unlink(newfile);
				return BACKUP_RETVAL.NO_SPC;
			} else {
				return BACKUP_RETVAL.CANT_COPY;
			}
		}
		return BACKUP_RETVAL.OK;	
	}
	
	public BACKUP_RETVAL link_file(string path,time_t mod_time) {
		
		//GLib.stdout.printf("Linkando %s a %s\n",Path.build_filename(this.last_backup,path),Path.build_filename(this.cbackup_path,path));
		
		var dest_path=Path.build_filename(this.cbackup_path,path);
		var retval=link(Path.build_filename(this.last_backup,path),dest_path);
		
		if (retval!=0) {
			if (retval==Posix.ENOSPC) {
				return BACKUP_RETVAL.NO_SPC;
			} else {
				return BACKUP_RETVAL.CANT_LINK;
			}
		}
		return BACKUP_RETVAL.OK;
	}

	public BACKUP_RETVAL create_folder(string path,time_t mod_time) {
	
		File dir2;
	
		try {
			dir2 = File.new_for_path(Path.build_filename(this.cbackup_path,path));
			dir2.make_directory_with_parents(null);
		} catch (IOError e) {
			if (e is IOError.NO_SPACE) {
				return BACKUP_RETVAL.NO_SPC;
			} else {
				return BACKUP_RETVAL.CANT_CREATE_FOLDER;
			}
		}
		
		return BACKUP_RETVAL.OK;
	}

	public BACKUP_RETVAL set_modtime(string path, time_t mod_time) {
		
		File dir2;
	
		dir2 = File.new_for_path(Path.build_filename(this.cbackup_path,path));
		
		dir2.set_attribute_uint64(FILE_ATTRIBUTE_TIME_MODIFIED,mod_time,0,null);
		dir2.set_attribute_uint64(FILE_ATTRIBUTE_TIME_ACCESS,mod_time,0,null);
		return BACKUP_RETVAL.OK;
	}

	public BACKUP_RETVAL abort_backup() {
		if (this.cfinal_path==null) {
			return BACKUP_RETVAL.NO_STARTED;
		}
		this.cfinal_path=null;
		return BACKUP_RETVAL.OK;
	}
}
