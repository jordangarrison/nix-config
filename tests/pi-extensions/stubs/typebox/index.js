// Stand-in for the TypeBox builders the extensions under test call. The real
// package is compiled into the pi binary. These return plain JSON Schema,
// which is all the tests look at.
export const Type = {
  Object: (properties, options = {}) => ({
    type: "object",
    properties,
    required: Object.keys(properties),
    ...options,
  }),
  String: (options = {}) => ({ type: "string", ...options }),
};
