output "folder_ids" {
  description = "Folder name (short) to folder id. Later stages read this."
  value       = { for k, f in google_folder.folder : k => f.name }
}

output "project_ids" {
  description = "Short project name to the real project id."
  value       = { for k, p in google_project.project : k => p.project_id }
}

output "project_numbers" {
  description = "Short project name to project number."
  value       = { for k, p in google_project.project : k => p.number }
}

output "summary" {
  value = { for k, p in google_project.project : "${local.folders[local.projects[k].folder]}/${p.name}" => p.project_id }
}
