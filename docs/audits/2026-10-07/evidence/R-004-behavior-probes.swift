import Foundation
@main struct AuditProbe {
 static func main() async throws {
  let fm = FileManager.default
  let root = URL(fileURLWithPath: "/private/tmp/nautica-audit-probes-2026-10-07-" + UUID().uuidString)
  try fm.createDirectory(at: root, withIntermediateDirectories: true)
  func dir(_ name: String) throws -> URL { let u=root.appendingPathComponent(name); try fm.createDirectory(at:u,withIntermediateDirectories:true); return u }
  func write(_ u:URL,_ s:String) throws { try Data(s.utf8).write(to:u) }
  var rows:[[String:Any]]=[]
  let src=try dir("replace-source"), dst=try dir("replace-destination")
  let missing=src.appendingPathComponent("sample.txt"), old=dst.appendingPathComponent("sample.txt")
  try write(old,"OLD DESTINATION")
  let replace=await FileOperationService.shared.copyItems([missing],to:dst,progress:Progress(totalUnitCount:1),resolutions:[missing:.replace])
  rows.append(["probe":"replace_missing_source","failed":replace.failed.count,"destination_exists":fm.fileExists(atPath:old.path),"destination_original_bytes": "OLD DESTINATION"])
  let absent=root.appendingPathComponent("never-existed"), right=try dir("mirror-right")
  let important=right.appendingPathComponent("important.txt");try write(important,"SYNTHETIC IMPORTANT")
  let plan=try await FolderSyncService.shared.compareFolders(leftURL:absent,rightURL:right,mode:.mirror)
  let syncResult=try await FolderSyncService.shared.executeSync(differences:plan,leftBaseURL:absent,rightBaseURL:right)
  rows.append(["probe":"mirror_missing_left","relative_paths":plan.map{$0.relativePath},"planned_actions":plan.map{$0.action.rawValue},"deleted":syncResult.deleted,"destination_exists":fm.fileExists(atPath:important.path)])
  let l2=try dir("sync-left"), r2=try dir("sync-right")
  let lf=l2.appendingPathComponent("version.txt"),rf=r2.appendingPathComponent("version.txt")
  try write(lf,"NEW CONTENT" );try write(rf,"OLD")
  try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:100)],ofItemAtPath:rf.path)
  let p2=try await FolderSyncService.shared.compareFolders(leftURL:l2,rightURL:r2,mode:.update)
  try fm.removeItem(at:lf)
  var failure=""
  do { _=try await FolderSyncService.shared.executeSync(differences:p2,leftBaseURL:l2,rightBaseURL:r2) } catch { failure=error.localizedDescription }
  rows.append(["probe":"sync_source_disappears","relative_paths":p2.map{$0.relativePath},"planned_actions":p2.map{$0.action.rawValue},"error":failure,"destination_exists":fm.fileExists(atPath:rf.path)])
  let l3=try dir("same-meta-left"),r3=try dir("same-meta-right")
  let a=l3.appendingPathComponent("same.txt"),b=r3.appendingPathComponent("same.txt")
  try write(a,"AAAA");try write(b,"BBBB")
  for u in [a,b] { try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:100)],ofItemAtPath:u.path) }
  let p3=try await FolderSyncService.shared.compareFolders(leftURL:l3,rightURL:r3,mode:.mirror)
  rows.append(["probe":"mirror_equal_metadata_different_bytes","statuses":p3.map{$0.status.label},"actions":p3.map{$0.action.rawValue},"contents_differ":try Data(contentsOf:a) != Data(contentsOf:b)])
  let selected=try dir("selected"),outside=try dir("outside-selection")
  let sentinel=outside.appendingPathComponent("sentinel.txt"),link=selected.appendingPathComponent("file-link")
  try write(sentinel,"SENTINEL MUST RETAIN BYTES")
  try fm.createSymbolicLink(at:link,withDestinationURL:sentinel)
  try await SecureFileDeletionService.shared.secureDelete(urls:[link],algorithm:.zeroFill)
  rows.append(["probe":"secure_delete_file_symlink","target_exists":fm.fileExists(atPath:sentinel.path),"target_bytes_after":try Data(contentsOf:sentinel).count,"selected_link_exists":(try? fm.attributesOfItem(atPath:link.path)) != nil])
  let outdir=try dir("outside-selection-directory"),child=outdir.appendingPathComponent("child.txt"),dlink=selected.appendingPathComponent("directory-link")
  try write(child,"OUTSIDE DIRECTORY SENTINEL"); try fm.createSymbolicLink(at:dlink,withDestinationURL:outdir)
  var directoryError=""
  do { try await SecureFileDeletionService.shared.secureDelete(urls:[dlink],algorithm:.zeroFill) } catch { directoryError=error.localizedDescription }
  rows.append(["error":directoryError,"probe":"secure_delete_directory_symlink","outside_directory_exists":fm.fileExists(atPath:outdir.path),"outside_child_exists":fm.fileExists(atPath:child.path)])
  let control=src.appendingPathComponent("good.txt"); try write(control,"CONTROL")
  let ok=await FileOperationService.shared.copyItems([control],to:dst,progress:Progress(totalUnitCount:1))
  rows.append(["probe":"ordinary_copy_control","succeeded":ok.succeeded.count,"source_preserved":try String(contentsOf:control,encoding:.utf8)=="CONTROL","destination_matches":try String(contentsOf:dst.appendingPathComponent("good.txt"),encoding:.utf8)=="CONTROL"])
  let data=try JSONSerialization.data(withJSONObject:["synthetic_only":true,"root":root.path,"results":rows],options:[.prettyPrinted,.sortedKeys]); FileHandle.standardOutput.write(data)
 }
}
