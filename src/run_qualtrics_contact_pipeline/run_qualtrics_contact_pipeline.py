from scripts import process_contacts_proc

# * run entry point
process_contacts_proc.main()

# # ! DEPRECATED: load sheet into pandas dataframe
# raw_contacts_df = analytic_utils.load_sheet_to_df(worksheet=raw_contacts_sheet)
# print(f"Raw df:\n {raw_contacts_df}\n")
# # print(raw_contacts_df.shape)

# # ! DEPRECATED transformation magic
# clean_contacts_df = analytic_utils.transform_df(
#     df=raw_contacts_df,
#     rename_map=config.analytic_params.rename_map,
#     bool_key=config.analytic_params.boolean_key,
#     bool_value=config.analytic_params.boolean_value,
# )
# print(f"Clean df:\n {clean_contacts_df}\n")
# # print(clean_contacts_df.shape)
